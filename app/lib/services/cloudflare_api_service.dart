import 'dart:convert';
import 'dart:io';

class CloudflareZone {
  final String id;
  final String name;
  final String accountId;

  const CloudflareZone({
    required this.id,
    required this.name,
    required this.accountId,
  });

  factory CloudflareZone.fromJson(Map<String, dynamic> json) {
    final account = (json['account'] as Map<String, dynamic>?) ?? {};
    return CloudflareZone(
      id: json['id'] as String,
      name: json['name'] as String,
      accountId: account['id'] as String? ?? '',
    );
  }
}

class CloudflareTunnelSummary {
  final String id;
  final String name;
  final String status;

  const CloudflareTunnelSummary({
    required this.id,
    required this.name,
    required this.status,
  });

  factory CloudflareTunnelSummary.fromJson(Map<String, dynamic> json) {
    return CloudflareTunnelSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      status: (json['status'] as String?) ?? 'inactive',
    );
  }
}

class CloudflareApiService {
  final String apiToken;
  final HttpClient _client;

  CloudflareApiService({
    required this.apiToken,
    HttpClient? client,
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  static const String _baseUrl = 'https://api.cloudflare.com/client/v4';

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final request = await _client.openUrl(method, uri);
    request.headers.set('Authorization', 'Bearer $apiToken');
    request.headers.set('Content-Type', 'application/json; charset=utf-8');

    if (body != null) {
      final jsonStr = jsonEncode(body);
      request.write(jsonStr);
    }

    final response = await request.close();
    final respText = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Cloudflare API 响应错误 (HTTP ${response.statusCode}): $respText',
        uri: uri,
      );
    }

    final json = jsonDecode(respText) as Map<String, dynamic>;
    if (json['success'] != true) {
      final errors = (json['errors'] as List?) ?? [];
      final msg = errors.isNotEmpty
          ? (errors.first['message'] ?? '未知错误')
          : 'API 请求失败';
      throw Exception('Cloudflare API 错误: $msg');
    }

    return json;
  }

  /// 验证 API Token 是否有效 (兼容 User API Token 与 Account API Token cfat_*)
  Future<bool> verifyToken() async {
    // 1. 优先尝试直接访问 Zones 列表 (Account Token 与拥有 Zone 权限的 Token 均能验证)
    try {
      final res = await _request('GET', '/zones?status=active&per_page=1');
      if (res['success'] == true) return true;
    } catch (_) {}

    // 2. 回退验证 User Token
    try {
      final res = await _request('GET', '/user/tokens/verify');
      final result = (res['result'] as Map<String, dynamic>?) ?? {};
      return result['status'] == 'active';
    } catch (_) {
      return false;
    }
  }

  /// 获取当前账号下所有激活的托管主域名 (Zones)
  Future<List<CloudflareZone>> listZones() async {
    final res = await _request('GET', '/zones?status=active&per_page=50');
    final list = (res['result'] as List?) ?? [];
    return list.map((e) => CloudflareZone.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取指定账户下的 Tunnel 列表
  Future<List<CloudflareTunnelSummary>> listTunnels(String accountId) async {
    final res = await _request('GET', '/accounts/$accountId/cfd_tunnel?is_deleted=false&per_page=50');
    final list = (res['result'] as List?) ?? [];
    return list
        .map((e) => CloudflareTunnelSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取隧道的运行长 Token (可直接用于拉起 cloudflared)
  Future<String> getTunnelToken(String accountId, String tunnelId) async {
    final res = await _request('GET', '/accounts/$accountId/cfd_tunnel/$tunnelId/token');
    return (res['result'] as String?) ?? '';
  }

  /// 自动在 Cloudflare Tunnel 中配置或追加一条 Ingress 路由映射
  /// 格式: hostname -> http://localhost:$localPort
  Future<void> bindTunnelRoute({
    required String accountId,
    required String tunnelId,
    required String hostname,
    required int localPort,
  }) async {
    // 1. 获取现有路由配置
    Map<String, dynamic>? existingConfig;
    try {
      final res = await _request('GET', '/accounts/$accountId/cfd_tunnel/$tunnelId/configurations');
      existingConfig = (res['result'] as Map<String, dynamic>?)?['config'] as Map<String, dynamic>?;
    } catch (_) {}

    final List<dynamic> ingressList = [];
    if (existingConfig != null && existingConfig['ingress'] is List) {
      ingressList.addAll(existingConfig['ingress'] as List);
    }

    // 移除已有相同 hostname 的旧规则以及最后的 catch-all 404
    ingressList.removeWhere((item) {
      if (item is Map) {
        if (item['hostname'] == hostname) return true;
        if (item.containsKey('service') && item['service'] == 'http_status:404') return true;
      }
      return false;
    });

    // 插入新规则
    ingressList.add({
      'hostname': hostname,
      'service': 'http://localhost:$localPort',
    });

    // 末尾追加兜底 404
    ingressList.add({
      'service': 'http_status:404',
    });

    // 2. 提交更新 Ingress 路由配置
    await _request(
      'PUT',
      '/accounts/$accountId/cfd_tunnel/$tunnelId/configurations',
      body: {
        'config': {
          'ingress': ingressList,
        },
      },
    );
  }

  /// 自动在 Cloudflare 域名的 DNS 解析记录中添加或更新 CNAME 记录
  /// 将 [hostname] (如 t.ghys.us.ci) CNAME 解析到 [tunnelId].cfargotunnel.com
  Future<void> upsertDnsCnameRecord({
    required String zoneId,
    required String hostname,
    required String tunnelId,
  }) async {
    final cnameTarget = '$tunnelId.cfargotunnel.com';

    // 1. 查找是否已存在相同记录
    final search = await _request(
      'GET',
      '/zones/$zoneId/dns_records?type=CNAME&name=$hostname',
    );
    final results = (search['result'] as List?) ?? [];

    final payload = {
      'type': 'CNAME',
      'name': hostname,
      'content': cnameTarget,
      'proxied': true, // 开启 Cloudflare 代理以自动提供免费 SSL 证书
      'ttl': 1,        // 1 = Auto TTL
    };

    if (results.isNotEmpty) {
      // 已存在，更新记录
      final recordId = results.first['id'] as String;
      await _request('PUT', '/zones/$zoneId/dns_records/$recordId', body: payload);
    } else {
      // 不存在，创建新记录
      await _request('POST', '/zones/$zoneId/dns_records', body: payload);
    }
  }

  void close() {
    _client.close();
  }
}

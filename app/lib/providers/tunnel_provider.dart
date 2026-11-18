import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/tunnel_model.dart';
import '../services/cloudflare_api_service.dart';
import '../services/dependency_service.dart';
import '../services/docker_service.dart';
import '../services/parsers.dart';
import '../services/port_monitor_service.dart';
import '../services/storage_service.dart';
import '../services/tunnel_engine.dart';
import '../services/usage_history_service.dart';

class TunnelProvider extends ChangeNotifier {
  final StorageService storage;
  final DependencyService deps;
  final PortMonitorService portMonitor;
  final DockerService docker;
  final TunnelEngine engine;
  final void Function(String title, String body) _notify;

  List<TunnelModel> tunnels = [];
  AppSettings settings = AppSettings();
  List<DockerContainer> dockerContainers = [];
  Map<String, PortStatus> portStatuses = {};
  int eventsToday = 0;
  final UsageHistory usage = UsageHistory();
  final Map<String, int> _lastSeenCounts = {};
  final Map<String, int> _lastSeenSuccess = {};
  final Set<String> _metricsLive = {};
  DateTime? _usageSavedAt;

  /// 历史统计写盘节流：最多每 20 秒落盘一次（退出时会强制保存）。
  void _persistUsage() {
    final now = DateTime.now();
    final last = _usageSavedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _usageSavedAt = now;
    unawaited(usage.saveTo(storage.usageHistoryFile));
  }
  bool cloudflaredReady = false;
  bool ngrokReady = false;

  /// 今日累计请求量取自持久化的历史统计，进程重启也不会归零。
  int get totalRequestsToday => usage.day(DateTime.now())?.total ?? 0;
  int get successRequestsToday => usage.day(DateTime.now())?.success ?? 0;
  int get errorRequestsToday =>
      (totalRequestsToday - successRequestsToday).clamp(0, totalRequestsToday);

  double get globalAvgLatencyMs {
    final active = tunnels.where((t) => t.status == TunnelStatus.running && t.avgLatencyMs > 0);
    if (active.isEmpty) return 0.0;
    final sum = active.fold<double>(0.0, (acc, t) => acc + t.avgLatencyMs);
    return sum / active.length;
  }
  List<CloudflareZone> cloudflareZones = [];
  List<CloudflareTunnelSummary> cloudflareTunnels = [];
  bool isSyncingCloudflare = false;

  int get runningCount =>
      tunnels.where((t) => t.status == TunnelStatus.running).length;

  double get onlineRate =>
      tunnels.isEmpty ? 0.0 : runningCount / tunnels.length;

  int get dockerTunnelCount =>
      tunnels.where((t) => t.dockerContainerName != null).length;

  int get localTunnelCount => tunnels.length - dockerTunnelCount;

  int get listeningPortCount =>
      portStatuses.values.where((p) => p.inUse).length;

  int get idlePortCount {
    final idle = tunnels.length - listeningPortCount;
    return idle > 0 ? idle : 0;
  }

  int _currentTab = 0;
  int get currentTab => _currentTab;
  set currentTab(int v) {
    _currentTab = v;
    notifyListeners();
  }

  String? _selectedLogTunnelId;
  String? get selectedLogTunnelId => _selectedLogTunnelId;
  set selectedLogTunnelId(String? v) {
    _selectedLogTunnelId = v;
    notifyListeners();
  }

  final Map<String, Process> _processes = {};
  final Map<String, Future<void>> _inFlightStarts = {};
  final Set<String> _manualStop = {};
  final Map<String, int> _retryCount = {};
  Timer? _inspectTimer;
  Timer? _dockerTimer;
  bool _disposed = false;

  TunnelProvider({
    required this.storage,
    required this.deps,
    PortMonitorService? portMonitor,
    DockerService? docker,
    TunnelEngine? engine,
    void Function(String title, String body)? notify,
  })  : portMonitor = portMonitor ?? PortMonitorService(),
        docker = docker ?? DockerService(),
        engine = engine ?? TunnelEngine(),
        _notify = notify ?? _noop;

  static void _noop(String a, String b) {}

  static Future<TunnelProvider> bootstrap(
          {void Function(String, String)? notify}) async =>
      TunnelProvider(
        storage: await StorageService.create(),
        deps: await DependencyService.create(),
        notify: notify,
      );

  Future<void> init() async {
    final config = await storage.load();
    settings = config.settings;
    for (final t in config.tunnels) {
      t.status = TunnelStatus.stopped;
      t.processPid = null;
      t.logs.clear();
      t.requestCount = 0;
      t.successCount = 0;
      t.errorCount = 0;
      t.metricsUrl = null;
    }
    tunnels = config.tunnels;
    await usage.loadFrom(storage.usageHistoryFile);
    _inspectTimer = Timer.periodic(
        const Duration(seconds: 6), (_) => inspectAllPorts());
    _dockerTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => refreshDocker());
    unawaited(_prepareDependencies());
    unawaited(refreshDocker());
    unawaited(portMonitor.killOrphanTunnels());
    if (settings.cloudflareApiToken.isNotEmpty) {
      unawaited(syncCloudflareAccount());
    }
    await inspectAllPorts();
    notifyListeners();
  }

  /// 使用 Cloudflare API Token 自动同步账号信息 (托管域名列表、已建 Tunnel 与 Tunnel Token)
  Future<bool> syncCloudflareAccount({String? token}) async {
    final effectiveToken = (token ?? settings.cloudflareApiToken).trim();
    if (effectiveToken.isEmpty) return false;

    isSyncingCloudflare = true;
    notifyListeners();

    final api = CloudflareApiService(apiToken: effectiveToken);
    try {
      final valid = await api.verifyToken();
      if (!valid) {
        throw Exception('Cloudflare API Token 验证未通过或状态非 active');
      }

      // 1. 获取托管的所有主域名 (Zones)
      final zones = await api.listZones();
      cloudflareZones = zones;

      String accountId = settings.cloudflareAccountId;
      if (accountId.isEmpty && zones.isNotEmpty) {
        accountId = zones.first.accountId;
        settings.cloudflareAccountId = accountId;
      }

      // 2. 获取 Tunnel 列表
      if (accountId.isNotEmpty) {
        final tunnelsList = await api.listTunnels(accountId);
        cloudflareTunnels = tunnelsList;

        // 如果设置中未指定 tunnelId，优先选择名为 easy-tunnel 或第一个可用隧道
        if (tunnelsList.isNotEmpty) {
          final matched = tunnelsList.firstWhere(
            (t) => t.name == 'easy-tunnel',
            orElse: () => tunnelsList.first,
          );
          settings.cloudflareTunnelId = matched.id;

          // 自动把运行需要的长 Tunnel Token 也自动拉取回填好！
          final runToken = await api.getTunnelToken(accountId, matched.id);
          if (runToken.isNotEmpty) {
            settings.cloudflareToken = runToken;
          }
        }
      }

      settings.cloudflareApiToken = effectiveToken;
      await _persist();
      isSyncingCloudflare = false;
      notifyListeners();
      return true;
    } catch (e) {
      isSyncingCloudflare = false;
      notifyListeners();
      rethrow;
    } finally {
      api.close();
    }
  }

  /// 全自动在 Cloudflare 添加 CNAME 解析与 Ingress 路由映射
  Future<void> autoBindCloudflareTunnelRoute({
    required String zoneId,
    required String hostname,
    required int targetPort,
  }) async {
    final token = settings.cloudflareApiToken.trim();
    final accountId = settings.cloudflareAccountId.trim();
    final tunnelId = settings.cloudflareTunnelId.trim();

    if (token.isEmpty || accountId.isEmpty || tunnelId.isEmpty) {
      throw Exception('缺少 Cloudflare API 凭据或未关联 Tunnel ID，请在配置中同步账户。');
    }

    final api = CloudflareApiService(apiToken: token);
    try {
      // 1. 自动在 DNS 中添加或更新 CNAME 记录
      await api.upsertDnsCnameRecord(
        zoneId: zoneId,
        hostname: hostname,
        tunnelId: tunnelId,
      );

      // 2. 自动在 Tunnel Ingress 路由表中添加映射: hostname -> http://localhost:$targetPort
      await api.bindTunnelRoute(
        accountId: accountId,
        tunnelId: tunnelId,
        hostname: hostname,
        localPort: targetPort,
      );
    } finally {
      api.close();
    }
  }

  Future<void> _prepareDependencies() async {
    try {
      await deps.ensureCloudflared();
      cloudflaredReady = true;
    } catch (_) {
      cloudflaredReady = false;
    }
    try {
      await deps.ensureNgrok();
      ngrokReady = true;
    } catch (_) {
      ngrokReady = false;
    }
    notifyListeners();
  }

  TunnelModel? tunnelById(String id) {
    for (final t in tunnels) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool isOrphanOccupied(TunnelModel t) {
    if (t.status != TunnelStatus.stopped) return false;
    final status = portStatuses[t.id];
    if (status?.inUse != true) return false;
    final name = (status?.processName ?? '').toLowerCase();
    return name.contains('cloudflared') || name.contains('ngrok');
  }

  int get conflictCount => tunnels.where(isOrphanOccupied).length;

  Future<void> _persist() =>
      storage.save(AppConfig(tunnels: tunnels, settings: settings));

  Future<void> addTunnel(TunnelModel t) async {
    tunnels.add(t);
    await _persist();
    notifyListeners();
    unawaited(_inspectOne(t));
  }

  Future<void> updateTunnel(TunnelModel t) async {
    final i = tunnels.indexWhere((x) => x.id == t.id);
    if (i >= 0) tunnels[i] = t;
    await _persist();
    notifyListeners();
  }

  Future<void> removeTunnel(String id) async {
    await stopTunnel(id);
    tunnels.removeWhere((t) => t.id == id);
    portStatuses.remove(id);
    if (_selectedLogTunnelId == id) _selectedLogTunnelId = null;
    await _persist();
    notifyListeners();
  }

  Future<PortStatus> inspectPort(int port) => portMonitor.inspect(port);

  Future<void> _inspectOne(TunnelModel t) async {
    try {
      portStatuses[t.id] = await portMonitor.inspect(t.targetPort);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> probeTunnelLatency(TunnelModel t) async {
    if (t.status != TunnelStatus.running) return;
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.openUrl('GET', Uri.parse('http://127.0.0.1:${t.targetPort}'));
      req.headers.set('User-Agent', 'EasyTunnel-Probe');
      final resp = await req.close();
      await resp.drain();
      client.close();
      sw.stop();
      final ms = (sw.elapsedMicroseconds / 1000.0).clamp(1.0, 9999.0);
      t.lastLatencyMs = ms;
      t.avgLatencyMs = t.avgLatencyMs == 0 ? ms : (t.avgLatencyMs * 0.7 + ms * 0.3);
      t.lastActiveTime = DateTime.now();
      notifyListeners();
    } catch (_) {
      sw.stop();
    }
  }

  Future<void> inspectAllPorts() async {
    for (final t in tunnels) {
      await _inspectOne(t);
      if (t.status == TunnelStatus.running) {
        unawaited(probeTunnelLatency(t));
        unawaited(pollTunnelMetrics(t));
      }
    }
  }

  Future<TunnelStats?> _fetchCloudflareStats(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode == HttpStatus.ok) {
        final body = await resp.transform(utf8.decoder).join();
        return parseCloudflarePrometheusMetrics(body);
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  Future<TunnelStats?> _fetchNgrokStats(String baseUrl) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final tunnelsReq = await client.getUrl(Uri.parse('$baseUrl/api/tunnels'));
      final tunnelsResp = await tunnelsReq.close();
      if (tunnelsResp.statusCode != HttpStatus.ok) {
        return null;
      }
      final tunnelsBody = await tunnelsResp.transform(utf8.decoder).join();
      final tunnelsJson = jsonDecode(tunnelsBody) as Map<String, dynamic>;

      Map<String, dynamic>? requestsJson;
      try {
        final reqsReq = await client.getUrl(Uri.parse('$baseUrl/api/requests/http'));
        final reqsResp = await reqsReq.close();
        if (reqsResp.statusCode == HttpStatus.ok) {
          final reqsBody = await reqsResp.transform(utf8.decoder).join();
          requestsJson = jsonDecode(reqsBody) as Map<String, dynamic>;
        }
      } catch (_) {}

      return parseNgrokMetrics(tunnelsJson, requestsJson);
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  Future<void> pollTunnelMetrics(TunnelModel t) async {
    if (t.status != TunnelStatus.running) return;

    TunnelStats? stats;
    try {
      if (t.provider == 'cloudflare') {
        final endpoints = <String>[
          if (t.metricsUrl != null) t.metricsUrl!,
          'http://127.0.0.1:${settings.metricsPort}/metrics',
          'http://127.0.0.1:20241/metrics',
          'http://127.0.0.1:20242/metrics',
          'http://127.0.0.1:20243/metrics',
        ];
        for (final url in endpoints) {
          stats = await _fetchCloudflareStats(url);
          if (stats != null) {
            t.metricsUrl = url;
            break;
          }
        }
      } else if (t.provider == 'ngrok') {
        final endpoints = <String>[
          if (t.metricsUrl != null) t.metricsUrl!,
          'http://127.0.0.1:4040',
          'http://127.0.0.1:4041',
        ];
        for (final base in endpoints) {
          stats = await _fetchNgrokStats(base);
          if (stats != null) {
            t.metricsUrl = base;
            break;
          }
        }
      }
    } catch (_) {
      return;
    }
    if (stats == null) return;

    _metricsLive.add(t.id);
    _applyStats(t, stats);
    notifyListeners();
  }

  /// 用一次采集结果更新隧道计数，并把新增的增量记入对应时间段。
  ///
  /// 穿透进程的 metrics 是累计值，进程重启后会归零，因此这里按增量方式
  /// 记入当前分钟/小时/天，避免一整天的流量堆进同一根柱子。
  void _applyStats(TunnelModel t, TunnelStats stats) {
    final lastTotal = _lastSeenCounts[t.id];
    final lastSuccess = _lastSeenSuccess[t.id] ?? 0;
    final total = stats.totalRequests;
    final restarted = lastTotal != null && total < lastTotal;

    final delta = lastTotal == null || restarted ? total : total - lastTotal;
    if (delta > 0) {
      final successDelta = lastTotal == null || restarted
          ? stats.successCount
          : (stats.successCount - lastSuccess).clamp(0, delta);
      usage.add(delta, success: successDelta);
      _persistUsage();
    }
    _lastSeenCounts[t.id] = total;
    _lastSeenSuccess[t.id] = stats.successCount;

    t.requestCount = total;
    t.successCount = stats.successCount;
    t.errorCount = stats.errorCount;

    if (stats.avgLatencyMs != null && stats.avgLatencyMs! > 0) {
      t.lastLatencyMs = stats.avgLatencyMs!;
      t.avgLatencyMs = t.avgLatencyMs == 0
          ? stats.avgLatencyMs!
          : (t.avgLatencyMs * 0.7 + stats.avgLatencyMs! * 0.3);
    }
  }

  /// 供概览柱状图使用的区间统计。
  UsageBucket usageInRange(DateTime start, DateTime end, String granularity) =>
      usage.range(start, end, granularity);

  Future<void> refreshDocker() async {
    dockerContainers = await docker.listContainers();
    notifyListeners();
  }

  String _resolveToken(TunnelModel t) {
    if (t.token != null && t.token!.isNotEmpty) return t.token!;
    return t.provider == 'cloudflare'
        ? settings.cloudflareToken
        : settings.ngrokToken;
  }

  void _appendLog(TunnelModel t, String line) {
    final metricsAddr = extractMetricsAddress(line);
    if (metricsAddr != null) {
      t.metricsUrl = t.provider == 'cloudflare'
          ? 'http://$metricsAddr/metrics'
          : 'http://$metricsAddr';
    }

    final lower = line.toLowerCase();
    final isHttpAccess = (RegExp(r'\b(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+/\S*', caseSensitive: false).hasMatch(line) ||
            lower.contains('status=') ||
            lower.contains('200 ok') ||
            lower.contains('-> 200')) &&
        !lower.contains('settings: map') &&
        !lower.contains('connectivity') &&
        !lower.contains('precheck');

    // 已能从本地 metrics 接口拿到精确累计值时，日志行不再重复计数。
    if (isHttpAccess && !_metricsLive.contains(t.id)) {
      final durationMatch = RegExp(r'\((\d+(?:\.\d+)?)ms\)').firstMatch(line);
      final ms = durationMatch != null
          ? double.tryParse(durationMatch.group(1)!)
          : null;
      if (ms != null && ms > 0) {
        t.lastLatencyMs = ms;
        t.avgLatencyMs = t.avgLatencyMs == 0 ? ms : (t.avgLatencyMs * 0.7 + ms * 0.3);
      }

      final isSuccess = lower.contains('200') ||
          lower.contains('201') ||
          lower.contains('204') ||
          lower.contains('304') ||
          lower.contains('301') ||
          lower.contains('302');
      final isError = !isSuccess &&
          (lower.contains('400') ||
              lower.contains('401') ||
              lower.contains('403') ||
              lower.contains('404') ||
              lower.contains('500') ||
              lower.contains('502') ||
              lower.contains('503'));

      t.requestCount++;
      if (isSuccess) t.successCount++;
      if (isError) t.errorCount++;
      usage.add(1, success: isSuccess ? 1 : 0, at: DateTime.now());
      _persistUsage();
      _lastSeenCounts[t.id] = t.requestCount;
      _lastSeenSuccess[t.id] = t.successCount;
    }

    final important = line.contains('ERR') ||
        line.contains('error') ||
        line.contains('failed') ||
        line.contains('Your quick Tunnel') ||
        line.contains('started tunnel') ||
        extractPublicUrl(line) != null;
    if (!settings.detailedLogs && !important) return;
    t.logs.add(line);
    if (t.logs.length > 200) {
      t.logs.removeRange(0, t.logs.length - 200);
    }
  }

  Future<void> startTunnel(String id, {bool isRetry = false}) {
    final current = tunnelById(id);
    if (current == null ||
        current.status == TunnelStatus.running ||
        current.status == TunnelStatus.starting) {
      return Future<void>.value();
    }
    final future = _startTunnel(id, isRetry: isRetry);
    _inFlightStarts[id] = future;
    return future.whenComplete(() {
      if (identical(_inFlightStarts[id], future)) {
        _inFlightStarts.remove(id);
      }
    });
  }

  Future<void> _startTunnel(String id, {required bool isRetry}) async {
    final t = tunnelById(id);
    if (t == null) return;
    if (t.status == TunnelStatus.running ||
        t.status == TunnelStatus.starting) {
      return;
    }
    if (!isRetry) {
      _manualStop.remove(id);
      _retryCount[id] = 0;
      await portMonitor.killOrphanTunnels(port: t.targetPort);
    }
    t.status = TunnelStatus.starting;
    t.publicUrl = null;
    t.lastError = null;
    t.logs.clear();
    t.requestCount = 0;
    t.successCount = 0;
    t.errorCount = 0;
    t.metricsUrl = null;
    _lastSeenCounts.remove(t.id);
    _lastSeenSuccess.remove(t.id);
    _metricsLive.remove(t.id);
    notifyListeners();

    var resolvedToken = '';
    try {
      resolvedToken = _resolveToken(t);
      if (t.provider == 'cloudflare' &&
          t.mode == 'custom' &&
          resolvedToken.isEmpty) {
        t.status = TunnelStatus.error;
        t.lastError = '专属隧道需要 Cloudflare Token，请先在系统设置中配置';
        notifyListeners();
        return;
      }
      final String exe;
      if (t.provider == 'cloudflare') {
        exe = await deps.resolveCloudflared();
      } else {
        exe = await deps.resolveNgrok();
      }
      if (_manualStop.contains(id) || tunnelById(id) == null) {
        final current = tunnelById(id);
        if (current != null) {
          current.status = TunnelStatus.stopped;
          current.processPid = null;
        }
        notifyListeners();
        return;
      }
      final effective =
          t.copyWith(token: resolvedToken.isEmpty ? null : resolvedToken);

      final process = await engine.start(
        effective,
        cloudflaredPath: t.provider == 'cloudflare' ? exe : deps.cloudflaredPath,
        ngrokPath: t.provider == 'ngrok' ? exe : deps.ngrokPath,
        onLine: (line) {
          if (_manualStop.contains(id) || tunnelById(id) == null) return;
          _appendLog(t, line);
          final lower = line.toLowerCase();
          if (lower.contains('is already online') ||
              lower.contains('err_ngrok_334')) {
            t.status = TunnelStatus.error;
            t.lastError =
                '该域名端点已被占用在线 (ERR_NGROK_334)，已自动为您清理本地冲突进程，请再次点击【启动】重试。';
            _notify('域名被占用', '${t.name}: 正在清理冲突进程，请重试启动');
            unawaited(portMonitor.killOrphanTunnels(port: t.targetPort));
          } else if (lower.contains('limited to 3 simultaneous') ||
              lower.contains('simultaneous ngrok agent sessions') ||
              lower.contains('agent sessions')) {
            t.status = TunnelStatus.error;
            t.lastError =
                'ngrok 在线会话数已超限 (免费版账号限制 3 个并发)，请先关闭其他正在运行的 ngrok 进程或在 ngrok 仪表盘 Agents 中断开旧会话。';
            _notify('ngrok 会话超限', '${t.name}: 免费版限制 3 个在线会话，请先关闭其他 ngrok');
          } else if (looksLikeAuthError(line)) {
            t.status = TunnelStatus.error;
            t.lastError = '认证失败，请检查 Token 配置';
            _notify('认证失败', '${t.name}: 请检查 Token 配置');
          }
          final domain = t.customDomain;
          if (t.mode == 'custom' && domain != null && domain.isNotEmpty) {
            final ready = t.provider == 'cloudflare'
                ? line.contains('Registered tunnel connection')
                : line.contains('Forwarding') && line.contains(domain);
            if (ready) {
              _markRunning(t, 'https://$domain');
            }
          }
          notifyListeners();
        },
        onUrl: (url) {
          if (_manualStop.contains(id) || tunnelById(id) == null) return;
          _markRunning(t, url);
        },
      );
      if (_manualStop.contains(id) || tunnelById(id) == null) {
        await engine.stop(process.pid);
        final current = tunnelById(id);
        if (current != null) {
          current.status = TunnelStatus.stopped;
          current.processPid = null;
        }
        notifyListeners();
        return;
      }
      _processes[id] = process;
      t.processPid = process.pid;
      process.exitCode.then((code) => _onProcessExit(id, process.pid, code));
      notifyListeners();
    } catch (e) {
      final message = resolvedToken.isEmpty
          ? '$e'
          : '$e'.replaceAll(resolvedToken, '****');
      t.status = TunnelStatus.error;
      t.lastError = message;
      notifyListeners();
      _notify('隧道启动失败', '${t.name}: $message');
    }
  }

  void _markRunning(TunnelModel t, String url) {
    if (_manualStop.contains(t.id) ||
        t.processPid == null ||
        t.status == TunnelStatus.error) {
      return;
    }
    if (t.status == TunnelStatus.running && t.publicUrl == url) return;
    t.status = TunnelStatus.running;
    t.publicUrl = url;
    _retryCount[t.id] = 0;
    eventsToday += 1;
    _notify('隧道已上线', '${t.name}\n$url');
    notifyListeners();
    unawaited(probeTunnelLatency(t));
    unawaited(pollTunnelMetrics(t));
  }

  /// 重连退避：2s/4s/8s（public 以便测试覆写为 Duration.zero）。
  Duration retryDelay(int attempt) => Duration(seconds: 1 << attempt);

  void _onProcessExit(String id, int pid, int code) {
    final t = tunnelById(id);
    if (t == null) {
      if (_processes[id]?.pid == pid) _processes.remove(id);
      return;
    }
    if (t.processPid != pid) return;
    _processes.remove(id);
    t.processPid = null;
    if (_manualStop.contains(id)) {
      t.status = TunnelStatus.stopped;
      notifyListeners();
      return;
    }
    final attempt = (_retryCount[id] ?? 0) + 1;
    _retryCount[id] = attempt;
    if (attempt > 3) {
      t.status = TunnelStatus.error;
      t.lastError = '进程异常退出 (exit $code)，重试 3 次失败';
      notifyListeners();
      _notify('隧道异常退出', '${t.name}: exit code $code');
      return;
    }
    t.status = TunnelStatus.reconnecting;
    notifyListeners();
    Timer(retryDelay(attempt), () {
      if (_manualStop.contains(id)) return;
      if (tunnelById(id)?.status == TunnelStatus.reconnecting) {
        startTunnel(id, isRetry: true);
      }
    });
  }

  Future<void> stopTunnel(String id) async {
    _manualStop.add(id);
    _retryCount[id] = 0;
    final t = tunnelById(id);
    final pid = t?.processPid;
    if (pid != null) {
      await engine.stop(pid);
    }
    // 深度彻底清理：无论 PID 是否丢失，强制终结针对该端口运行的 cloudflared.exe 与 ngrok.exe
    if (t != null) {
      await portMonitor.killOrphanTunnels(port: t.targetPort);
    }
    _processes.remove(id);
    if (t != null) {
      t.status = TunnelStatus.stopped;
      t.processPid = null;
      t.publicUrl = null;
    }
    notifyListeners();
  }

  Future<void> killOccupant(String id) async {
    final status = portStatuses[id];
    if (status?.pid == null) return;
    final ok = await portMonitor.killProcessTree(status!.pid!);
    if (ok) {
      eventsToday += 1;
      _notify('端口已释放',
          '已终止 ${status.processName ?? '进程'} (PID ${status.pid})');
    }
    await _inspectOne(tunnelById(id)!);
  }

  Future<void> stopAll() async {
    final pending = _inFlightStarts.values
        .map((f) => f.catchError((_) {}))
        .toList();
    if (pending.isNotEmpty) {
      // Never let a slow dependency download block app exit indefinitely.
      await Future.wait(pending).timeout(
        const Duration(seconds: 5),
        onTimeout: () => const <void>[],
      );
    }
    for (final t in List.of(tunnels)) {
      await stopTunnel(t.id);
    }
    // 退出前全局兜底清理孤儿进程，绝不残留
    await portMonitor.killOrphanTunnels();
  }

  Future<void> saveSettings() async {
    await _persist();
    notifyListeners();
  }

  /// 供 UI 层清空某条隧道日志（notifyListeners 是 @protected，外部不可直接调用）。
  void clearLogs(String id) {
    tunnelById(id)?.logs.clear();
    notifyListeners();
  }

  /// 供设置页重新检测/下载依赖。
  Future<void> recheckDependencies() => _prepareDependencies();

  String newId() => const Uuid().v4();

  @override
  void dispose() {
    _disposed = true;
    _inspectTimer?.cancel();
    _dockerTimer?.cancel();
    _usageSavedAt = null;
    unawaited(usage.saveTo(storage.usageHistoryFile));
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}

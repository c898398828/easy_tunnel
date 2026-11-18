class DockerContainer {
  final String id;
  final String name;
  final Set<int> hostPorts;
  final String status;

  const DockerContainer({
    required this.id,
    required this.name,
    required this.hostPorts,
    required this.status,
  });

  String get label => hostPorts.isEmpty ? name : '$name:${hostPorts.first}';
}

/// 从 `netstat -ano -p tcp` 输出中找出处于 LISTENING 且监听 [port] 的 PID。
int? parseNetstatListeningPid(String output, int port) {
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (!line.startsWith('TCP')) continue;
    final cols = line.split(RegExp(r'\s+'));
    if (cols.length < 5) continue;
    if (cols[3] != 'LISTENING') continue;
    final local = cols[1];
    final sep = local.lastIndexOf(':');
    if (sep <= 0) continue;
    final localPort = int.tryParse(local.substring(sep + 1));
    if (localPort != port) continue;
    return int.tryParse(cols.last);
  }
  return null;
}

/// 从 `tasklist /FO CSV /NH` 输出中取第一行的进程名（第一个引号字段）。
String? parseTasklistName(String csvOutput) {
  for (final raw in csvOutput.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = RegExp(r'^"([^"]+)"').firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}

/// 解析 `docker ps --format "{{.ID}}|{{.Names}}|{{.Ports}}|{{.Status}}"` 输出。
List<DockerContainer> parseDockerPs(String output) {
  final result = <DockerContainer>[];
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split('|');
    if (parts.length < 4) continue;
    final ports = <int>{};
    for (final m in RegExp(r':(\d+)->').allMatches(parts[2])) {
      final p = int.tryParse(m.group(1)!);
      if (p != null) ports.add(p);
    }
    result.add(DockerContainer(
      id: parts[0],
      name: parts[1],
      hostPorts: ports,
      status: parts[3],
    ));
  }
  return result;
}

/// 从任意一行子进程输出中提取分配到的公网 URL。
String? extractPublicUrl(String line) {
  final cf = RegExp(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com').firstMatch(line);
  if (cf != null) return cf.group(0);
  final ng = RegExp(r'https://[a-zA-Z0-9.-]+\.ngrok(?:-free)?\.(?:app|dev)')
      .firstMatch(line);
  if (ng != null) return ng.group(0);
  return null;
}

/// 判断一行日志是否为认证/Token 错误。
bool looksLikeAuthError(String line) {
  final l = line.toLowerCase();
  return l.contains('authentication failed') ||
      l.contains('invalid token') ||
      l.contains('invalid authtoken') ||
      l.contains('err_ngrok_401') ||
      l.contains('unauthorized');
}

class TunnelStats {
  final int totalRequests;
  final int successCount;
  final int errorCount;
  final double? avgLatencyMs;

  const TunnelStats({
    required this.totalRequests,
    required this.successCount,
    required this.errorCount,
    this.avgLatencyMs,
  });
}

/// 解析 Cloudflare Prometheus metrics 文本输出
TunnelStats? parseCloudflarePrometheusMetrics(String body) {
  final totalMatch = RegExp(r'^cloudflared_tunnel_total_requests\s+(\d+)', multiLine: true).firstMatch(body);
  if (totalMatch == null) return null;
  final total = int.tryParse(totalMatch.group(1)!) ?? 0;

  final errMatch = RegExp(r'^cloudflared_tunnel_request_errors\s+(\d+)', multiLine: true).firstMatch(body);
  final errors = (errMatch != null ? int.tryParse(errMatch.group(1)!) : 0) ?? 0;
  final successes = (total - errors).clamp(0, total);

  return TunnelStats(
    totalRequests: total,
    successCount: successes,
    errorCount: errors,
  );
}

/// 解析 ngrok /api/tunnels 和 /api/requests/http 输出
TunnelStats? parseNgrokMetrics(Map<String, dynamic> tunnelsJson, [Map<String, dynamic>? requestsJson]) {
  final tunnels = tunnelsJson['tunnels'] as List?;
  if (tunnels == null || tunnels.isEmpty) return null;

  var total = 0;
  for (final t in tunnels) {
    if (t is Map<String, dynamic>) {
      final metrics = t['metrics'] as Map<String, dynamic>?;
      final http = metrics?['http'] as Map<String, dynamic>?;
      final count = (http?['count'] as num?)?.toInt() ?? 0;
      total += count;
    }
  }

  var successes = total;
  var errors = 0;
  double? avgLatencyMs;

  if (requestsJson != null) {
    final requests = requestsJson['requests'] as List?;
    if (requests != null && requests.isNotEmpty) {
      var reqSuccess = 0;
      var reqError = 0;
      var totalDurationNs = 0.0;
      var durationCount = 0;

      for (final r in requests) {
        if (r is Map<String, dynamic>) {
          final resp = r['response'] as Map<String, dynamic>?;
          final code = resp?['status_code'] as int? ?? 0;
          if (code > 0) {
            if (code < 400) {
              reqSuccess++;
            } else {
              reqError++;
            }
          }
          final dur = (r['duration'] as num?)?.toDouble();
          if (dur != null && dur > 0) {
            totalDurationNs += dur;
            durationCount++;
          }
        }
      }

      final sampledTotal = reqSuccess + reqError;
      if (sampledTotal > 0) {
        final errorRatio = reqError / sampledTotal;
        errors = (total * errorRatio).round();
        successes = (total - errors).clamp(0, total);
      }
      if (durationCount > 0) {
        avgLatencyMs = (totalDurationNs / durationCount) / 1000000.0;
      }
    }
  }

  return TunnelStats(
    totalRequests: total,
    successCount: successes,
    errorCount: errors,
    avgLatencyMs: avgLatencyMs,
  );
}

/// 从输出行中提取 metrics / web service 监听端口地址
String? extractMetricsAddress(String line) {
  final cf = RegExp(r'Starting metrics server on ([^\s/]+)').firstMatch(line);
  if (cf != null) return cf.group(1);

  final ng = RegExp(r'obj=web\s+addr=([^\s]+)').firstMatch(line);
  if (ng != null) return ng.group(1);

  return null;
}

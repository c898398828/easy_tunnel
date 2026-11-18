enum TunnelStatus { stopped, starting, running, reconnecting, error }

class TunnelModel {
  final String id;
  String name;
  int targetPort;
  String? dockerContainerName;
  String provider; // 'cloudflare' | 'ngrok'
  String mode; // 'quick' | 'custom'
  String? customDomain;
  String? token;
  TunnelStatus status;
  String? publicUrl;
  int? processPid;
  String? lastError;
  final List<String> logs;

  // 运行态性能与监控数据 (延迟、请求统计等)
  int requestCount;
  int successCount;
  int errorCount;
  double avgLatencyMs;
  double lastLatencyMs;
  DateTime? lastActiveTime;
  String? metricsUrl;

  double get successRate =>
      requestCount == 0 ? 1.0 : (successCount / requestCount).clamp(0.0, 1.0);

  String get latencyDisplay =>
      avgLatencyMs > 0 ? '${avgLatencyMs.toStringAsFixed(0)}ms' : (lastLatencyMs > 0 ? '${lastLatencyMs.toStringAsFixed(0)}ms' : '--');

  TunnelModel({
    required this.id,
    required this.name,
    required this.targetPort,
    this.dockerContainerName,
    this.provider = 'cloudflare',
    this.mode = 'quick',
    this.customDomain,
    this.token,
    this.status = TunnelStatus.stopped,
    this.publicUrl,
    this.processPid,
    this.lastError,
    List<String>? logs,
    this.requestCount = 0,
    this.successCount = 0,
    this.errorCount = 0,
    this.avgLatencyMs = 0.0,
    this.lastLatencyMs = 0.0,
    this.lastActiveTime,
    this.metricsUrl,
  }) : logs = logs ?? [];

  TunnelModel copyWith({
    String? name,
    int? targetPort,
    String? dockerContainerName,
    String? provider,
    String? mode,
    String? customDomain,
    String? token,
  }) {
    return TunnelModel(
      id: id,
      name: name ?? this.name,
      targetPort: targetPort ?? this.targetPort,
      dockerContainerName: dockerContainerName ?? this.dockerContainerName,
      provider: provider ?? this.provider,
      mode: mode ?? this.mode,
      customDomain: customDomain ?? this.customDomain,
      token: token ?? this.token,
      status: status,
      publicUrl: publicUrl,
      processPid: processPid,
      lastError: lastError,
      logs: logs,
      requestCount: requestCount,
      successCount: successCount,
      errorCount: errorCount,
      avgLatencyMs: avgLatencyMs,
      lastLatencyMs: lastLatencyMs,
      lastActiveTime: lastActiveTime,
      metricsUrl: metricsUrl,
    );
  }

  factory TunnelModel.fromJson(Map<String, dynamic> json) {
    return TunnelModel(
      id: json['id'] as String,
      name: json['name'] as String,
      targetPort: json['targetPort'] as int,
      dockerContainerName: json['dockerContainerName'] as String?,
      provider: (json['provider'] as String?) ?? 'cloudflare',
      mode: (json['mode'] as String?) ?? 'quick',
      customDomain: json['customDomain'] as String?,
      token: json['token'] as String?,
      status: TunnelStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => TunnelStatus.stopped,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetPort': targetPort,
        'dockerContainerName': dockerContainerName,
        'provider': provider,
        'mode': mode,
        'customDomain': customDomain,
        'token': token,
        'status': status.name,
      };
}

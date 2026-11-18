import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/models/tunnel_model.dart';
import 'package:easy_tunnel/providers/tunnel_provider.dart';
import 'package:easy_tunnel/services/dependency_service.dart';
import 'package:easy_tunnel/services/docker_service.dart';
import 'package:easy_tunnel/services/port_monitor_service.dart';
import 'package:easy_tunnel/services/storage_service.dart';
import 'package:easy_tunnel/services/tunnel_engine.dart';

class _FakeStorage extends StorageService {
  AppConfig stored = AppConfig();
  _FakeStorage() : super(File('unused.json'));

  @override
  Future<AppConfig> load() async => stored;

  @override
  Future<void> save(AppConfig config) async {
    stored = config;
  }
}

void main() {
  late _FakeStorage storage;
  late TunnelProvider provider;

  setUp(() {
    storage = _FakeStorage();
    provider = TunnelProvider(
      storage: storage,
      deps: DependencyService(Directory.systemTemp),
      portMonitor: PortMonitorServiceStub(),
      docker: DockerServiceStub(),
    );
  });

  test('addTunnel 持久化并可查询', () async {
    await provider.addTunnel(
        TunnelModel(id: 'a', name: 'web', targetPort: 8080));
    expect(provider.tunnels.length, 1);
    expect(provider.tunnelById('a')?.name, 'web');
    expect(storage.stored.tunnels.length, 1);
  });

  test('removeTunnel 删除并持久化', () async {
    await provider.addTunnel(
        TunnelModel(id: 'a', name: 'web', targetPort: 8080));
    await provider.removeTunnel('a');
    expect(provider.tunnels, isEmpty);
    expect(storage.stored.tunnels, isEmpty);
  });

  test('conflictCount 只统计被隧道进程占用的端口', () async {
    await provider.addTunnel(
        TunnelModel(id: 'a', name: 'web', targetPort: 8080));
    provider.portStatuses['a'] = const PortStatus(
        port: 8080, inUse: true, pid: 1, processName: 'node.exe');
    expect(provider.conflictCount, 0);
    provider.portStatuses['a'] = const PortStatus(
        port: 8080, inUse: true, pid: 2, processName: 'cloudflared.exe');
    expect(provider.conflictCount, 1);
    provider.tunnels.first.status = TunnelStatus.running;
    expect(provider.conflictCount, 0);
  });

  test('cloudflared 专属隧道在 Registered tunnel connection 后上线', () async {
    final engine = _CapturingEngine();
    final p = TunnelProvider(
      storage: storage,
      deps: _FakeDeps(),
      engine: engine,
      portMonitor: PortMonitorServiceStub(),
      docker: DockerServiceStub(),
    );
    await p.addTunnel(TunnelModel(
      id: 'cf',
      name: 'web',
      targetPort: 8080,
      provider: 'cloudflare',
      mode: 'custom',
      customDomain: 'a.example.com',
      token: 'cf-token',
    ));
    await p.startTunnel('cf');
    expect(engine.startCount, 1);

    engine.onLine!(
        '2026-11-13T00:00:00Z INF Registered tunnel connection connIndex=0');
    final t = p.tunnelById('cf')!;
    expect(t.status, TunnelStatus.running);
    expect(t.publicUrl, 'https://a.example.com');
    await p.stopAll();
    p.dispose();
  });

  test('ngrok 专属隧道在 Forwarding 自定义域名后上线', () async {
    final engine = _CapturingEngine();
    final p = TunnelProvider(
      storage: storage,
      deps: _FakeDeps(),
      engine: engine,
      portMonitor: PortMonitorServiceStub(),
      docker: DockerServiceStub(),
    );
    await p.addTunnel(TunnelModel(
      id: 'ng',
      name: 'web',
      targetPort: 8080,
      provider: 'ngrok',
      mode: 'custom',
      customDomain: 'a.example.com',
      token: 'ng-token',
    ));
    await p.startTunnel('ng');
    expect(engine.startCount, 1);

    engine.onLine!('Forwarding https://a.example.com -> http://127.0.0.1:8080');
    final t = p.tunnelById('ng')!;
    expect(t.status, TunnelStatus.running);
    expect(t.publicUrl, 'https://a.example.com');
    await p.stopAll();
    p.dispose();
  });

  test('cloudflared 专属隧道缺少 Token 时直接报错且不启动进程', () async {
    final engine = _CountingEngine();
    final p = TunnelProvider(
      storage: storage,
      deps: _FakeDeps(),
      engine: engine,
      portMonitor: PortMonitorServiceStub(),
      docker: DockerServiceStub(),
    );
    await p.addTunnel(TunnelModel(
      id: 'no-token',
      name: 'web',
      targetPort: 8080,
      provider: 'cloudflare',
      mode: 'custom',
      customDomain: 'a.example.com',
    ));
    await p.startTunnel('no-token');

    final t = p.tunnelById('no-token')!;
    expect(t.status, TunnelStatus.error);
    expect(t.lastError, '专属隧道需要 Cloudflare Token，请先在系统设置中配置');
    expect(engine.startCount, 0);
    p.dispose();
  });

  test('进程异常退出按指数退避重试，最多 3 次后置 error', () async {
    final engine = _CountingEngine();
    final fast = _FastRetryProvider(
      storage: storage,
      deps: _FakeDeps(),
      engine: engine,
      portMonitor: PortMonitorServiceStub(),
      docker: DockerServiceStub(),
    );
    await fast.addTunnel(
        TunnelModel(id: 'x', name: 'web', targetPort: 8080));
    await fast.startTunnel('x');

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (fast.tunnelById('x')!.status != TunnelStatus.error &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(engine.startCount, 4);
    expect(fast.tunnelById('x')!.status, TunnelStatus.error);
    fast.dispose();
  });

  test('依赖解析期间停止则放弃启动，不产生进程', () async {
    final deps = _BlockingDeps();
    final engine = _CountingEngine();
    final raced = TunnelProvider(
      storage: storage,
      deps: deps,
      engine: engine,
      portMonitor: PortMonitorServiceStub(),
      docker: DockerServiceStub(),
    );
    await raced.addTunnel(
        TunnelModel(id: 'y', name: 'web', targetPort: 8080));

    final startFuture = raced.startTunnel('y');
    await raced.stopTunnel('y');
    deps.completer.complete();
    await startFuture;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.startCount, 0);
    expect(raced.tunnelById('y')!.status, TunnelStatus.stopped);
    raced.dispose();
  });

  test('cloudflared 启动自检日志不误增请求数并正确捕获 metrics 地址', () async {
    final engine = _CapturingEngine();
    final p = TunnelProvider(
      storage: storage,
      deps: _FakeDeps(),
      engine: engine,
      portMonitor: PortMonitorServiceStub(),
      docker: DockerServiceStub(),
    );
    await p.addTunnel(TunnelModel(
      id: 'cf-diag',
      name: 'web',
      targetPort: 8080,
      provider: 'cloudflare',
      mode: 'quick',
    ));
    await p.startTunnel('cf-diag');

    // 模拟 cloudflared 启动自检日志
    engine.onLine!('INF Settings: map[no-autoupdate:true protocol:quic url:http://127.0.0.1:8080]');
    engine.onLine!('INF | TCP Connectivity region1.v2.argotunnel.com PASS HTTP/2 connection successful |');
    engine.onLine!('INF precheck component="TCP Connectivity" details="HTTP/2 connection successful"');
    engine.onLine!('INF Starting metrics server on 127.0.0.1:20242/metrics');

    final t = p.tunnelById('cf-diag')!;
    expect(t.requestCount, 0);
    expect(t.metricsUrl, 'http://127.0.0.1:20242/metrics');
    expect(p.totalRequestsToday, 0);

    // 模拟真实 HTTP 请求日志
    engine.onLine!('GET /api/test HTTP/1.1 200 OK (15ms)');
    expect(t.requestCount, 1);
    expect(t.successCount, 1);
    expect(p.totalRequestsToday, 1);
    expect(p.successRequestsToday, 1);

    await p.stopAll();
    p.dispose();
  });
}

class PortMonitorServiceStub extends PortMonitorService {
  PortMonitorServiceStub()
      : super(runner: (e, a) async => ProcessResult(0, 0, '', ''));
}

class DockerServiceStub extends DockerService {
  DockerServiceStub()
      : super(runner: (e, a) async => ProcessResult(0, 0, '', ''));
}

class _FakeDeps extends DependencyService {
  _FakeDeps() : super(Directory.systemTemp);

  @override
  Future<String> resolveCloudflared() async => 'cmd';

  @override
  Future<String> resolveNgrok() async => 'cmd';
}

class _BlockingDeps extends DependencyService {
  final Completer<void> completer = Completer<void>();
  _BlockingDeps() : super(Directory.systemTemp);

  @override
  Future<String> resolveCloudflared() async {
    await completer.future;
    return 'cmd';
  }
}

class _CountingEngine extends TunnelEngine {
  int startCount = 0;

  @override
  Future<Process> start(
    TunnelModel tunnel, {
    required String cloudflaredPath,
    required String ngrokPath,
    required void Function(String line) onLine,
    required void Function(String url) onUrl,
  }) {
    startCount += 1;
    return Process.start('cmd', ['/c', 'exit', '1']);
  }
}

class _CapturingEngine extends TunnelEngine {
  int startCount = 0;
  void Function(String line)? onLine;
  void Function(String url)? onUrl;

  @override
  Future<Process> start(
    TunnelModel tunnel, {
    required String cloudflaredPath,
    required String ngrokPath,
    required void Function(String line) onLine,
    required void Function(String url) onUrl,
  }) {
    startCount += 1;
    this.onLine = onLine;
    this.onUrl = onUrl;
    return Process.start('cmd', ['/c', 'ping', '-n', '20', '127.0.0.1']);
  }
}

class _FastRetryProvider extends TunnelProvider {
  _FastRetryProvider({
    required super.storage,
    required super.deps,
    required super.engine,
    super.portMonitor,
    super.docker,
  });

  @override
  Duration retryDelay(int attempt) => Duration.zero;
}

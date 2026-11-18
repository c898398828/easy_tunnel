import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:easy_tunnel/models/tunnel_model.dart';
import 'package:easy_tunnel/providers/tunnel_provider.dart';
import 'package:easy_tunnel/services/dependency_service.dart';
import 'package:easy_tunnel/services/docker_service.dart';
import 'package:easy_tunnel/services/port_monitor_service.dart';
import 'package:easy_tunnel/services/storage_service.dart';
import 'package:easy_tunnel/ui/widgets/tunnel_card.dart';

class _FakeStorage extends StorageService {
  _FakeStorage() : super(File('unused.json'));

  @override
  Future<AppConfig> load() async => AppConfig();

  @override
  Future<void> save(AppConfig config) async {}
}

TunnelProvider _provider() => TunnelProvider(
      storage: _FakeStorage(),
      deps: DependencyService(Directory.systemTemp),
      portMonitor: _PortMonitorStub(),
      docker: _DockerStub(),
    );

class _PortMonitorStub extends PortMonitorService {
  _PortMonitorStub()
      : super(runner: (e, a) async => ProcessResult(0, 0, '', ''));
}

class _DockerStub extends DockerService {
  _DockerStub() : super(runner: (e, a) async => ProcessResult(0, 0, '', ''));
}

Future<void> _pumpCard(
  WidgetTester tester,
  TunnelModel tunnel, {
  double width = 620,
}) async {
  final provider = _provider();
  await tester.pumpWidget(
    ChangeNotifierProvider<TunnelProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: TunnelCard(tunnel: tunnel)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('超长隧道名与容器名不会撑破卡片布局', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const longName = 'rd_after-order-sync-order-sync-1-very-long-name-for-testing';
    await _pumpCard(
      tester,
      TunnelModel(
        id: 'long',
        name: longName,
        targetPort: 18000,
        dockerContainerName: longName,
      ),
    );

    expect(tester.takeException(), isNull);

    // 名称被压缩为单行并省略显示，完整文本仍保留在 Tooltip 中。
    final nameText = tester.widget<Text>(find.text(longName).first);
    expect(nameText.maxLines, 1);
    expect(nameText.overflow, TextOverflow.ellipsis);
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('窄窗口下运行中的指标区也不会溢出', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tunnel = TunnelModel(
      id: 'running',
      name: 'rd_after-order-sync-order-sync-1',
      targetPort: 18000,
      dockerContainerName: 'rd_after-order-sync-order-sync-1',
      status: TunnelStatus.running,
      publicUrl: 'https://example.trycloudflare.com',
    )..requestCount = 120
      ..successCount = 118
      ..avgLatencyMs = 18;

    await _pumpCard(tester, tunnel, width: 520);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/models/tunnel_model.dart';
import 'package:easy_tunnel/services/storage_service.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('easy_tunnel_test');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('save 后 load 还原配置', () async {
    final file = File('${tmp.path}/config.json');
    final svc = StorageService(file);
    final cfg = AppConfig(
      tunnels: [TunnelModel(id: 'a', name: 'web', targetPort: 8080)],
      settings: AppSettings(cloudflareToken: 'CF', ngrokToken: 'NG'),
    );
    await svc.save(cfg);
    final loaded = await svc.load();
    expect(loaded.tunnels.single.id, 'a');
    expect(loaded.settings.cloudflareToken, 'CF');
    expect(loaded.settings.ngrokToken, 'NG');
    expect(loaded.settings.closeToTray, isTrue);
  });

  test('文件不存在时返回默认配置', () async {
    final svc = StorageService(File('${tmp.path}/none.json'));
    final cfg = await svc.load();
    expect(cfg.tunnels, isEmpty);
    expect(cfg.settings.detailedLogs, isTrue);
  });

  test('JSON 损坏时返回默认配置', () async {
    final file = File('${tmp.path}/bad.json');
    await file.writeAsString('{not json');
    final cfg = await StorageService(file).load();
    expect(cfg.tunnels, isEmpty);
  });

  test('损坏的单条隧道被跳过且 settings 保留', () async {
    final file = File('${tmp.path}/config.json');
    await file.writeAsString('''
{
  "tunnels": [
    {"id": "a", "name": "web", "targetPort": 8080},
    {"id": "bad"},
    {"name": "no-id", "targetPort": 1234}
  ],
  "settings": {"cloudflareToken": "CF", "detailedLogs": false}
}
''');
    final cfg = await StorageService(file).load();
    expect(cfg.tunnels.length, 1);
    expect(cfg.tunnels.single.id, 'a');
    expect(cfg.settings.cloudflareToken, 'CF');
    expect(cfg.settings.detailedLogs, isFalse);
  });

  test('JSON 损坏时备份为 .bak 并返回默认配置', () async {
    final file = File('${tmp.path}/bad.json');
    await file.writeAsString('{not json');
    final cfg = await StorageService(file).load();
    expect(cfg.tunnels, isEmpty);
    final bak = File('${file.path}.bak');
    expect(await bak.exists(), isTrue);
    expect(await bak.readAsString(), '{not json');
  });
}

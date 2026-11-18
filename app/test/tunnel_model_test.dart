import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/models/tunnel_model.dart';

void main() {
  test('toJson/fromJson 往返保持全部持久化字段', () {
    final t = TunnelModel(
      id: 'u1',
      name: '前端',
      targetPort: 8080,
      dockerContainerName: 'ops-center-web',
      provider: 'ngrok',
      mode: 'custom',
      customDomain: 'app.example.com',
      token: 'tok_123',
    );
    final restored = TunnelModel.fromJson(t.toJson());
    expect(restored.id, 'u1');
    expect(restored.name, '前端');
    expect(restored.targetPort, 8080);
    expect(restored.dockerContainerName, 'ops-center-web');
    expect(restored.provider, 'ngrok');
    expect(restored.mode, 'custom');
    expect(restored.customDomain, 'app.example.com');
    expect(restored.token, 'tok_123');
    expect(restored.status, TunnelStatus.stopped);
    expect(restored.logs, isEmpty);
  });

  test('fromJson 容忍缺失可选字段并使用默认值', () {
    final restored = TunnelModel.fromJson({
      'id': 'u2',
      'name': 'api',
      'targetPort': 3000,
    });
    expect(restored.provider, 'cloudflare');
    expect(restored.mode, 'quick');
    expect(restored.token, isNull);
    expect(restored.status, TunnelStatus.stopped);
  });

  test('copyWith 只覆盖传入字段', () {
    final t = TunnelModel(id: 'u3', name: 'a', targetPort: 80, token: 'old');
    final c = t.copyWith(token: 'new');
    expect(c.token, 'new');
    expect(c.name, 'a');
    expect(t.token, 'old');
  });
}

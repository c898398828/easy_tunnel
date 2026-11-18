import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/models/tunnel_model.dart';
import 'package:easy_tunnel/services/tunnel_engine.dart';

void main() {
  TunnelModel t({
    String provider = 'cloudflare',
    String mode = 'quick',
    int port = 8080,
    String? token,
    String? domain,
  }) =>
      TunnelModel(
        id: 'x',
        name: 'n',
        targetPort: port,
        provider: provider,
        mode: mode,
        token: token,
        customDomain: domain,
      );

  test('cloudflare quick 命令', () {
    final inv = TunnelEngine.buildInvocation(
      t(),
      cloudflaredPath: r'C:\bin\cloudflared.exe',
      ngrokPath: r'C:\bin\ngrok.exe',
    );
    expect(inv.executable, r'C:\bin\cloudflared.exe');
    expect(inv.arguments,
        ['tunnel', '--url', 'http://127.0.0.1:8080', '--no-autoupdate']);
  });

  test('cloudflare custom 带 token 走 run --token', () {
    final inv = TunnelEngine.buildInvocation(
      t(mode: 'custom', token: 'TOK'),
      cloudflaredPath: 'cf',
      ngrokPath: 'ng',
    );
    expect(inv.arguments, ['tunnel', 'run', '--token', 'TOK']);
  });

  test('ngrok 基础命令与 token/domain 追加', () {
    final inv = TunnelEngine.buildInvocation(
      t(provider: 'ngrok', mode: 'custom', token: 'NT', domain: 'a.example.com'),
      cloudflaredPath: 'cf',
      ngrokPath: r'C:\bin\ngrok.exe',
    );
    expect(inv.executable, r'C:\bin\ngrok.exe');
    expect(inv.arguments, [
      'http',
      '127.0.0.1:8080',
      '--log',
      'stdout',
      '--authtoken',
      'NT',
      '--domain',
      'a.example.com',
    ]);
  });
}

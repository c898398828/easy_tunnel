import 'dart:convert';
import 'dart:io';

import '../models/tunnel_model.dart';
import 'parsers.dart';

class TunnelInvocation {
  final String executable;
  final List<String> arguments;

  const TunnelInvocation({required this.executable, required this.arguments});
}

class TunnelEngine {
  static TunnelInvocation buildInvocation(
    TunnelModel tunnel, {
    required String cloudflaredPath,
    required String ngrokPath,
  }) {
    if (tunnel.provider == 'cloudflare') {
      final token = tunnel.token;
      if (tunnel.mode == 'custom' && token != null && token.isNotEmpty) {
        return TunnelInvocation(
            executable: cloudflaredPath,
            arguments: ['tunnel', 'run', '--token', token]);
      }
      return TunnelInvocation(executable: cloudflaredPath, arguments: [
        'tunnel',
        '--url',
        'http://127.0.0.1:${tunnel.targetPort}',
        '--no-autoupdate',
      ]);
    }

    final args = <String>[
      'http',
      '127.0.0.1:${tunnel.targetPort}',
      '--log',
      'stdout',
    ];
    final token = tunnel.token;
    if (token != null && token.isNotEmpty) {
      args.addAll(['--authtoken', token]);
    }
    if (tunnel.mode == 'custom' &&
        tunnel.customDomain != null &&
        tunnel.customDomain!.isNotEmpty) {
      args.addAll(['--domain', tunnel.customDomain!]);
    }
    return TunnelInvocation(executable: ngrokPath, arguments: args);
  }

  Future<Process> start(
    TunnelModel tunnel, {
    required String cloudflaredPath,
    required String ngrokPath,
    required void Function(String line) onLine,
    required void Function(String url) onUrl,
  }) async {
    final inv = buildInvocation(tunnel,
        cloudflaredPath: cloudflaredPath, ngrokPath: ngrokPath);
    final process = await Process.start(inv.executable, inv.arguments);

    void handle(String line) {
      if (line.trim().isEmpty) return;
      onLine(line);
      final url = extractPublicUrl(line);
      if (url != null) onUrl(url);
    }

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(handle);
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(handle);
    return process;
  }

  Future<void> stop(int pid) async {
    try {
      await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
    } catch (_) {}
  }
}

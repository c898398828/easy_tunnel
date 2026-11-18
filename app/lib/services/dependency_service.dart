import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage_service.dart';

class DependencyService {
  final Directory binDir;
  Future<void>? _cloudflaredDownload;
  Future<void>? _ngrokDownload;

  DependencyService(this.binDir);

  static Future<DependencyService> create([String? customBinPath]) async {
    if (customBinPath != null && customBinPath.isNotEmpty) {
      final d = Directory(customBinPath);
      await d.create(recursive: true);
      return DependencyService(d);
    }

    final baseDir = getPreferredBaseDir();
    final bin = Directory(p.join(baseDir.path, 'bin'));
    await bin.create(recursive: true);

    // 检查旧的 AppData 目录，如果存在已有二进制，自动迁移避免重复下载
    try {
      final oldSupport = await getApplicationSupportDirectory();
      final oldBin = Directory(p.join(oldSupport.path, 'bin'));
      if (await oldBin.exists()) {
        for (final name in ['cloudflared.exe', 'ngrok.exe']) {
          final oldExe = File(p.join(oldBin.path, name));
          final targetExe = File(p.join(bin.path, name));
          if (await oldExe.exists() && !await targetExe.exists()) {
            await oldExe.copy(targetExe.path);
          }
        }
      }
    } catch (_) {}

    return DependencyService(bin);
  }

  String get cloudflaredPath => p.join(binDir.path, 'cloudflared.exe');
  String get ngrokPath => p.join(binDir.path, 'ngrok.exe');

  Future<String?> _findOnPath(String exe) async {
    try {
      final r = await Process.run('where', [exe]);
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String?) ?? '';
      for (final line in out.split(RegExp(r'\r?\n'))) {
        if (line.trim().isNotEmpty) return line.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<String> resolveCloudflared() async {
    final onPath = await _findOnPath('cloudflared.exe');
    if (onPath != null) return onPath;
    await ensureCloudflared();
    return cloudflaredPath;
  }

  Future<String> resolveNgrok() async {
    final onPath = await _findOnPath('ngrok.exe');
    if (onPath != null) return onPath;
    await ensureNgrok();
    return ngrokPath;
  }

  Future<void> ensureCloudflared({void Function(double)? onProgress}) {
    final inFlight = _cloudflaredDownload;
    if (inFlight != null) return inFlight;
    final future = _ensureCloudflared(onProgress)
        .whenComplete(() => _cloudflaredDownload = null);
    _cloudflaredDownload = future;
    return future;
  }

  Future<void> _ensureCloudflared(void Function(double)? onProgress) async {
    final target = File(cloudflaredPath);
    if (await target.exists()) return;
    await _download(
      Uri.parse(
          'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'),
      target,
      onProgress,
    );
  }

  Future<void> ensureNgrok({void Function(double)? onProgress}) {
    final inFlight = _ngrokDownload;
    if (inFlight != null) return inFlight;
    final future =
        _ensureNgrok(onProgress).whenComplete(() => _ngrokDownload = null);
    _ngrokDownload = future;
    return future;
  }

  Future<void> _ensureNgrok(void Function(double)? onProgress) async {
    final target = File(ngrokPath);
    if (await target.exists()) return;
    final zip = File(p.join(binDir.path, 'ngrok.zip'));
    await _download(
      Uri.parse(
          'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip'),
      zip,
      onProgress,
    );
    final r = await Process.run('tar', ['-xf', zip.path, '-C', binDir.path]);
    try {
      await zip.delete();
    } catch (_) {}
    if (r.exitCode != 0 || !await target.exists()) {
      try {
        await target.delete();
      } catch (_) {}
      try {
        await zip.delete();
      } catch (_) {}
      throw Exception('ngrok 解压失败');
    }
  }

  Future<void> _download(
    Uri url,
    File target,
    void Function(double)? onProgress,
  ) async {
    await binDir.create(recursive: true);
    final part = File('${target.path}.part');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 60);
    IOSink? sink;
    var completed = false;
    try {
      final req = await client.getUrl(url);
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) {
        throw HttpException('下载失败 HTTP ${resp.statusCode}: $url');
      }
      sink = part.openWrite();
      final total = resp.contentLength;
      var received = 0;
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      if (total > 0 && received != total) {
        throw HttpException('下载不完整: $received/$total bytes: $url');
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await part.rename(target.path);
      completed = true;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      if (!completed) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }
}

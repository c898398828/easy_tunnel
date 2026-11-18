import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tunnel_model.dart';

class AppSettings {
  String cloudflareToken;
  String cloudflareApiToken;
  String cloudflareAccountId;
  String cloudflareTunnelId;
  String ngrokToken;
  bool detailedLogs;
  bool launchAtStartup;
  bool closeToTray;
  int metricsPort;
  int inspectIntervalSeconds;

  AppSettings({
    this.cloudflareToken = '',
    this.cloudflareApiToken = '',
    this.cloudflareAccountId = '',
    this.cloudflareTunnelId = '',
    this.ngrokToken = '',
    this.detailedLogs = true,
    this.launchAtStartup = false,
    this.closeToTray = true,
    this.metricsPort = 20241,
    this.inspectIntervalSeconds = 6,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        cloudflareToken: (json['cloudflareToken'] as String?) ?? '',
        cloudflareApiToken: (json['cloudflareApiToken'] as String?) ?? '',
        cloudflareAccountId: (json['cloudflareAccountId'] as String?) ?? '',
        cloudflareTunnelId: (json['cloudflareTunnelId'] as String?) ?? '',
        ngrokToken: (json['ngrokToken'] as String?) ?? '',
        detailedLogs: (json['detailedLogs'] as bool?) ?? true,
        launchAtStartup: (json['launchAtStartup'] as bool?) ?? false,
        closeToTray: (json['closeToTray'] as bool?) ?? true,
        metricsPort: (json['metricsPort'] as int?) ?? 20241,
        inspectIntervalSeconds:
            (json['inspectIntervalSeconds'] as int?) ?? 6,
      );

  Map<String, dynamic> toJson() => {
        'cloudflareToken': cloudflareToken,
        'cloudflareApiToken': cloudflareApiToken,
        'cloudflareAccountId': cloudflareAccountId,
        'cloudflareTunnelId': cloudflareTunnelId,
        'ngrokToken': ngrokToken,
        'detailedLogs': detailedLogs,
        'launchAtStartup': launchAtStartup,
        'closeToTray': closeToTray,
        'metricsPort': metricsPort,
        'inspectIntervalSeconds': inspectIntervalSeconds,
      };
}

class AppConfig {
  List<TunnelModel> tunnels;
  AppSettings settings;

  AppConfig({List<TunnelModel>? tunnels, AppSettings? settings})
      : tunnels = tunnels ?? [],
        settings = settings ?? AppSettings();

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final tunnels = <TunnelModel>[];
    final rawTunnels = json['tunnels'];
    if (rawTunnels is List) {
      for (final entry in rawTunnels) {
        try {
          tunnels.add(TunnelModel.fromJson(entry as Map<String, dynamic>));
        } catch (_) {
          // Skip malformed tunnel entries, keep the rest of the config.
        }
      }
    }
    final rawSettings = json['settings'];
    return AppConfig(
      tunnels: tunnels,
      settings: AppSettings.fromJson(
          rawSettings is Map<String, dynamic> ? rawSettings : {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'tunnels': tunnels.map((t) => t.toJson()).toList(),
        'settings': settings.toJson(),
      };
}

Directory getPreferredBaseDir() {
  try {
    final exeFile = File(Platform.resolvedExecutable);
    final exeDir = exeFile.parent;
    final testDir = Directory(p.join(exeDir.path, '.write_test'));
    testDir.createSync();
    testDir.deleteSync();
    return exeDir;
  } catch (_) {
    return Directory(p.join(
      Platform.environment['APPDATA'] ?? '.',
      'EasyTunnel',
    ));
  }
}

class StorageService {
  final File file;
  Future<void> _writeChain = Future.value();

  StorageService(this.file);

  /// 使用历史统计文件与配置同目录存放，随配置目录一起迁移。
  File get usageHistoryFile => File(p.join(file.parent.path, 'usage_history.json'));

  static Future<StorageService> create([String? customConfigPath]) async {
    if (customConfigPath != null && customConfigPath.isNotEmpty) {
      final f = File(customConfigPath);
      await f.parent.create(recursive: true);
      return StorageService(f);
    }

    final baseDir = getPreferredBaseDir();
    final dataDir = Directory(p.join(baseDir.path, 'data'));
    await dataDir.create(recursive: true);
    final targetFile = File(p.join(dataDir.path, 'config.json'));

    // 如果新目录不存在配置，但旧 AppData 目录存在，自动平滑迁移
    if (!await targetFile.exists()) {
      try {
        final oldSupport = await getApplicationSupportDirectory();
        final oldFile = File(p.join(oldSupport.path, 'config.json'));
        if (await oldFile.exists()) {
          await oldFile.copy(targetFile.path);
        }
      } catch (_) {}
    }

    return StorageService(targetFile);
  }

  Future<AppConfig> load() async {
    try {
      if (!await file.exists()) return AppConfig();
      final text = await file.readAsString();
      final json = jsonDecode(text) as Map<String, dynamic>;
      return AppConfig.fromJson(json);
    } catch (_) {
      try {
        await file.copy('${file.path}.bak');
      } catch (_) {}
      return AppConfig();
    }
  }

  Future<void> save(AppConfig config) {
    final write = _writeChain.then((_) => _writeAtomically(config));
    // Keep the chain alive after a failure so later saves still run.
    _writeChain = write.catchError((_) {});
    return write;
  }

  Future<void> _writeAtomically(AppConfig config) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    final sink = tmp.openWrite();
    try {
      sink.write(
          const JsonEncoder.withIndent('  ').convert(config.toJson()));
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    await tmp.rename(file.path);
  }
}

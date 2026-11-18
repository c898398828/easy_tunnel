import 'dart:io';

import 'parsers.dart';

typedef CommandRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

class PortStatus {
  final int port;
  final bool inUse;
  final int? pid;
  final String? processName;

  const PortStatus({
    required this.port,
    required this.inUse,
    this.pid,
    this.processName,
  });
}

class PortMonitorService {
  final CommandRunner _run;

  PortMonitorService({CommandRunner? runner}) : _run = runner ?? Process.run;

  Future<PortStatus> inspect(int port) async {
    final net = await _run('netstat', ['-ano', '-p', 'tcp']);
    final pid = parseNetstatListeningPid((net.stdout as String?) ?? '', port);
    if (pid == null || pid == 0) {
      return PortStatus(port: port, inUse: false);
    }
    String? name;
    try {
      final tl = await _run(
          'tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
      name = parseTasklistName((tl.stdout as String?) ?? '');
    } catch (_) {}
    return PortStatus(port: port, inUse: true, pid: pid, processName: name);
  }

  Future<bool> killProcessTree(int pid) async {
    final r = await _run('taskkill', ['/F', '/T', '/PID', '$pid']);
    return r.exitCode == 0;
  }

  /// 彻底清理针对特定端口（或所有）残留的 cloudflared.exe 与 ngrok.exe 孤儿进程
  Future<void> killOrphanTunnels({int? port}) async {
    if (!Platform.isWindows) return;
    try {
      final String filter;
      if (port != null) {
        filter =
            'Get-CimInstance Win32_Process -Filter "Name = \'cloudflared.exe\' or Name = \'ngrok.exe\'" | Where-Object { \$_.CommandLine -like "*:$port*" -or \$_.CommandLine -like "*127.0.0.1:$port*" } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }';
      } else {
        filter =
            'Get-CimInstance Win32_Process -Filter "Name = \'cloudflared.exe\' or Name = \'ngrok.exe\'" | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }';
      }
      await _run('powershell', ['-NoProfile', '-Command', filter]);
    } catch (_) {}
  }
}

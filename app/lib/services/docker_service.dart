import 'dart:io';

import 'parsers.dart';
import 'port_monitor_service.dart';

class DockerService {
  final CommandRunner _run;

  DockerService({CommandRunner? runner}) : _run = runner ?? Process.run;

  Future<List<DockerContainer>> listContainers() async {
    try {
      final r = await _run('docker',
          ['ps', '--format', '{{.ID}}|{{.Names}}|{{.Ports}}|{{.Status}}']);
      if (r.exitCode != 0) return const [];
      return parseDockerPs((r.stdout as String?) ?? '');
    } catch (_) {
      return const [];
    }
  }
}

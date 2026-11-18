import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/services/docker_service.dart';

void main() {
  test('listContainers 解析正常输出', () async {
    final svc = DockerService(runner: (exe, args) async {
      expect(exe, 'docker');
      expect(args, ['ps', '--format', '{{.ID}}|{{.Names}}|{{.Ports}}|{{.Status}}']);
      return ProcessResult(
          0, 0, 'abc|web|0.0.0.0:8080->80/tcp|Up 1 minute\n', '');
    });
    final list = await svc.listContainers();
    expect(list.single.name, 'web');
    expect(list.single.hostPorts, {8080});
  });

  test('docker 不存在时返回空列表不抛异常', () async {
    final svc = DockerService(runner: (exe, args) async {
      throw ProcessException(exe, args, 'not found');
    });
    expect(await svc.listContainers(), isEmpty);
  });

  test('非零退出码返回空列表', () async {
    final svc = DockerService(
        runner: (exe, args) async => ProcessResult(0, 1, '', 'error'));
    expect(await svc.listContainers(), isEmpty);
  });
}

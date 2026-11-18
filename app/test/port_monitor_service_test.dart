import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/services/port_monitor_service.dart';

void main() {
  const netstatOut = '  TCP    127.0.0.1:3000    0.0.0.0:0    LISTENING    9412\r\n';

  test('inspect 返回占用进程名与 PID', () async {
    final calls = <String>[];
    final svc = PortMonitorService(runner: (exe, args) async {
      calls.add('$exe ${args.join(' ')}');
      if (exe == 'netstat') return ProcessResult(0, 0, netstatOut, '');
      if (exe == 'tasklist') {
        return ProcessResult(0, 0, '"node.exe","9412","Console","1","45,232 K"\r\n', '');
      }
      return ProcessResult(0, 1, '', '');
    });
    final s = await svc.inspect(3000);
    expect(s.inUse, isTrue);
    expect(s.pid, 9412);
    expect(s.processName, 'node.exe');
    expect(calls.first, 'netstat -ano -p tcp');
    expect(calls[1], 'tasklist /FI PID eq 9412 /FO CSV /NH');
  });

  test('inspect 端口空闲', () async {
    final svc = PortMonitorService(runner: (exe, args) async {
      return ProcessResult(0, 0, '', '');
    });
    final s = await svc.inspect(3000);
    expect(s.inUse, isFalse);
    expect(s.pid, isNull);
  });

  test('killProcessTree 成功时返回 true', () async {
    List<String>? captured;
    final svc = PortMonitorService(runner: (exe, args) async {
      captured = [exe, ...args];
      return ProcessResult(0, 0, '', '');
    });
    expect(await svc.killProcessTree(9412), isTrue);
    expect(captured, ['taskkill', '/F', '/T', '/PID', '9412']);
  });
}

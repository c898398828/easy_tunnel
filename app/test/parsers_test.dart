import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/services/parsers.dart';

void main() {
  group('parseNetstatListeningPid', () {
    const netstat = '''
活动连接

  协议  本地地址          外部地址        状态           PID
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1234
  TCP    127.0.0.1:3000         0.0.0.0:0              LISTENING       9412
  TCP    127.0.0.1:3000         127.0.0.1:51000        ESTABLISHED     9412
  TCP    [::]:8080              [::]:0                 LISTENING       5678
  TCP    [::1]:3001             [::]:0                 LISTENING       7777
  UDP    0.0.0.0:3002           *:*                                    8888
''';

    test('命中 IPv4 监听端口', () {
      expect(parseNetstatListeningPid(netstat, 3000), 9412);
    });

    test('命中 IPv6 通配监听端口', () {
      expect(parseNetstatListeningPid(netstat, 8080), 5678);
    });

    test('命中 IPv6 回环监听端口', () {
      expect(parseNetstatListeningPid(netstat, 3001), 7777);
    });

    test('忽略 ESTABLISHED 与 UDP 行', () {
      expect(parseNetstatListeningPid(netstat, 51000), isNull);
      expect(parseNetstatListeningPid(netstat, 3002), isNull);
    });

    test('端口未监听返回 null', () {
      expect(parseNetstatListeningPid(netstat, 9999), isNull);
    });
  });

  group('parseTasklistName', () {
    test('解析 CSV 首行进程名', () {
      expect(parseTasklistName('"node.exe","9412","Console","1","45,232 K"\r\n'), 'node.exe');
    });

    test('未找到进程时返回 null', () {
      expect(parseTasklistName('信息: 没有运行的任务匹配指定标准。\r\n'), isNull);
    });
  });

  group('parseDockerPs', () {
    test('解析多容器与多端口映射', () {
      const out = 'abc123|ops-center-web|0.0.0.0:8080->80/tcp, [::]:8080->80/tcp|Up 2 hours\n'
          'def456|ops-center-api|127.0.0.1:4000->4000/tcp|Up 5 minutes\n'
          'ghi789|idle-box||Exited (0) 1 hour ago\n';
      final list = parseDockerPs(out);
      expect(list.length, 3);
      expect(list[0].name, 'ops-center-web');
      expect(list[0].hostPorts, {8080});
      expect(list[1].hostPorts, {4000});
      expect(list[2].hostPorts, isEmpty);
    });

    test('空输出返回空列表', () {
      expect(parseDockerPs(''), isEmpty);
    });
  });

  group('extractPublicUrl', () {
    test('捕获 Cloudflare Quick 域名', () {
      expect(
        extractPublicUrl('|  https://rapid-alpine-tunnel.trycloudflare.com   |'),
        'https://rapid-alpine-tunnel.trycloudflare.com',
      );
    });

    test('捕获 ngrok 域名', () {
      expect(
        extractPublicUrl('Forwarding  https://abcd-1234.ngrok-free.app -> http://127.0.0.1:3000'),
        'https://abcd-1234.ngrok-free.app',
      );
      expect(
        extractPublicUrl('url=https://myapp.ngrok.app'),
        'https://myapp.ngrok.app',
      );
    });

    test('无 URL 行返回 null', () {
      expect(extractPublicUrl('INF no address yet'), isNull);
    });
  });

  group('looksLikeAuthError', () {
    test('识别 ngrok 认证失败', () {
      expect(looksLikeAuthError('ERROR: authentication failed'), isTrue);
      expect(looksLikeAuthError('ERR_NGROK_401: failed to authenticate'), isTrue);
    });

    test('识别 cloudflare token 无效', () {
      expect(looksLikeAuthError('failed to parse token: invalid token'), isTrue);
      expect(looksLikeAuthError('Unauthorized'), isTrue);
    });

    test('普通日志不误报', () {
      expect(looksLikeAuthError('Registered tunnel connection'), isFalse);
    });
  });

  group('parseCloudflarePrometheusMetrics', () {
    test('解析请求总数与错误数', () {
      const metricsText = '''
# HELP cloudflared_tunnel_request_errors Count of error proxying to origin
# TYPE cloudflared_tunnel_request_errors counter
cloudflared_tunnel_request_errors 2
# HELP cloudflared_tunnel_total_requests Amount of requests proxied through all the tunnels
# TYPE cloudflared_tunnel_total_requests counter
cloudflared_tunnel_total_requests 100
''';
      final stats = parseCloudflarePrometheusMetrics(metricsText);
      expect(stats, isNotNull);
      expect(stats!.totalRequests, 100);
      expect(stats.errorCount, 2);
      expect(stats.successCount, 98);
    });

    test('无匹配时返回 null', () {
      expect(parseCloudflarePrometheusMetrics('some other text'), isNull);
    });
  });

  group('parseNgrokMetrics', () {
    test('解析 ngrok 隧道指标与请求列表', () {
      final tunnels = {
        'tunnels': [
          {
            'name': 'command_line',
            'metrics': {
              'http': {'count': 50}
            }
          }
        ]
      };
      final reqs = {
        'requests': [
          {'response': {'status_code': 200}, 'duration': 10000000}, // 10ms
          {'response': {'status_code': 200}, 'duration': 20000000}, // 20ms
          {'response': {'status_code': 500}, 'duration': 30000000}, // 30ms
        ]
      };
      final stats = parseNgrokMetrics(tunnels, reqs);
      expect(stats, isNotNull);
      expect(stats!.totalRequests, 50);
      expect(stats.avgLatencyMs, closeTo(20.0, 0.1));
      // 1/3 错误率，50 * (1/3) ~ 17 错误, 33 成功
      expect(stats.errorCount, 17);
      expect(stats.successCount, 33);
    });
  });

  group('extractMetricsAddress', () {
    test('提取 cloudflared metrics 地址', () {
      expect(
        extractMetricsAddress('2026-11-14T05:27:19Z INF Starting metrics server on 127.0.0.1:20242/metrics'),
        '127.0.0.1:20242',
      );
    });

    test('提取 ngrok web 地址', () {
      expect(
        extractMetricsAddress('t=2026-11-14T13:27:56+0800 lvl=info msg="starting web service" obj=web addr=127.0.0.1:4041 allow_hosts=[]'),
        '127.0.0.1:4041',
      );
    });

    test('无关日志返回 null', () {
      expect(extractMetricsAddress('just an ordinary log'), isNull);
    });
  });
}

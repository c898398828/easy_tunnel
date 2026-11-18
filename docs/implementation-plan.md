# Easy Tunnel (内网穿透管家) 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一款 Windows 桌面端 Flutter 应用，支持多隧道并发内网穿透（Cloudflare / ngrok）、Docker 端口智能识别、端口冲突一键强杀、系统托盘常驻，UI 采用现代化暗黑极简风格。

**Architecture:** Flutter 纯原生进程托管架构：Dart 通过 `Process` 直接拉起 `cloudflared.exe` / `ngrok.exe` / `docker.exe` / `netstat` / `taskkill`，实时解析子进程输出流捕获公网域名；无后台守护进程，应用退出即级联清理所有子进程。

**Tech Stack:** Flutter (stable ≥3.35) + Dart 3、provider、window_manager、tray_manager、local_notifier、uuid、path_provider、path。

**Spec:** `easy_tunnel/docs/easy-tunnel-design.md`（同一内容也存于 `docs/superpowers/specs/2026-11-13-easy-tunnel-design.md`）

## 全局约束

- 目标平台：Windows 10/11 x86_64；Flutter stable 最新版；本机 Visual Studio 2022 构建工具已安装。
- 项目根目录：`D:\projects\ops-center\easy_tunnel\app`（Flutter 包名 `easy_tunnel`）。
- UI 文案全部中文；应用显示名 `Easy Tunnel 助手`。
- 暗色主题色值（与 `easy_tunnel/prototype.html` 一致，必须逐字使用）：
  - 窗口底 `#0D0F12`、侧边栏 `#121418`、卡片 `#16191F`、边框 `#21252F`、亮边框 `#2C3340`
  - 主文字 `#EDEDED`、次级 `#8A93A5`、弱化 `#525A6B`
  - 绿 `#10B981`、蓝 `#3B82F6`、琥珀 `#F59E0B`、天蓝 `#38BDF8`、红 `#EF4444`、靛 `#818CF8`
- Docker 探测为可选功能，Docker 未安装/未启动时不得崩溃（返回空列表）。
- Token 在日志输出与 UI 展示中必须脱敏（仅显示前 4 后 4 位）。
- 日志环形缓冲上限 200 行/隧道。
- 每个任务完成后必须 `flutter analyze` 零告警；提交信息结尾必须加：
  `Co-Authored-By: BaoCode <noreply@baocode.dev>`
- 提交只 `git add` 本任务涉及的文件，禁止 `git add -A`（仓库有其他无关改动）。

## 文件结构总览

```
easy_tunnel/app/
├── pubspec.yaml
├── assets/tray_icon.ico                # 从 windows/runner/resources/app_icon.ico 复制
├── lib/
│   ├── main.dart                       # 入口：窗口初始化、通知初始化、bootstrap provider
│   ├── app.dart                        # EasyTunnelApp + AppShell（标题栏/侧边栏/内容/日志抽屉）
│   ├── theme.dart                      # AppColors 常量 + buildTheme()
│   ├── models/tunnel_model.dart        # TunnelModel / TunnelStatus / copyWith / json
│   ├── services/
│   │   ├── parsers.dart                # 纯函数：netstat/tasklist/docker ps/URL 正则解析 + DockerContainer
│   │   ├── port_monitor_service.dart   # PortStatus / inspect / killProcessTree
│   │   ├── docker_service.dart         # listContainers
│   │   ├── tunnel_engine.dart          # buildInvocation / start / stop
│   │   ├── dependency_service.dart     # 二进制探测、自动下载、PATH 查找
│   │   ├── storage_service.dart        # AppSettings / AppConfig / load / save
│   │   └── tray_window_service.dart    # 托盘菜单、关闭到托盘、窗口事件
│   ├── providers/tunnel_provider.dart  # 状态编排：CRUD/启停/日志/定时探测/重连
│   └── ui/
│       ├── title_bar.dart              # 自定义标题栏（拖动/最小化/最大化/关闭）
│       ├── sidebar.dart                # 左侧导航
│       ├── dashboard_page.dart         # 概览：统计卡片 + 装饰图表 + 隧道卡片
│       ├── tunnels_page.dart           # 隧道管理列表
│       ├── settings_page.dart          # 系统设置
│       └── widgets/
│           ├── stat_card.dart          # 统计卡片（含环形进度）
│           ├── activity_chart.dart     # 装饰性堆叠柱状图
│           ├── tunnel_card.dart        # 隧道卡片（状态/端口/冲突强杀/URL复制）
│           ├── log_drawer.dart         # 底部日志抽屉
│           └── new_tunnel_dialog.dart  # 新建穿透弹窗（Docker 下拉 + 端口探测）
└── test/
    ├── parsers_test.dart
    ├── tunnel_model_test.dart
    ├── port_monitor_service_test.dart
    ├── docker_service_test.dart
    ├── tunnel_engine_test.dart
    ├── storage_service_test.dart
    └── tunnel_provider_test.dart
```

---

### Task 1: 安装 Flutter SDK 并初始化项目骨架

**Files:**
- Create: `easy_tunnel/app/`（flutter create 生成）
- Modify: `easy_tunnel/app/pubspec.yaml`
- Create: `easy_tunnel/app/assets/tray_icon.ico`

**Interfaces:**
- Produces: 可编译的 Flutter Windows 项目骨架；所有第三方依赖已加入；`assets/tray_icon.ico` 可用于托盘。

- [ ] **Step 1: 检查并安装 Flutter SDK**

```bash
flutter --version 2>/dev/null || echo "FLUTTER_MISSING"
```

若输出 `FLUTTER_MISSING`，用 PowerShell 安装最新 stable（下载地址从官方 releases JSON 动态解析）：

```powershell
$rel = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
$hash = $rel.current_release.stable
$archive = $rel.releases | Where-Object { $_.hash -eq $hash -and $_.archive -like '*stable.zip' } | Select-Object -First 1
$url = 'https://storage.googleapis.com/flutter_infra_release/releases/' + $archive.archive
Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\flutter-stable.zip"
Expand-Archive "$env:TEMP\flutter-stable.zip" -DestinationPath 'D:\dev' -Force
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';D:\dev\flutter\bin', 'User')
```

当前 bash 会话内生效：

```bash
export PATH="/d/dev/flutter/bin:$PATH"
flutter --version
```

- [ ] **Step 2: 验证 Windows 桌面工具链**

```bash
flutter doctor
```

Expected: `Visual Studio - develop Windows apps` 一项为 ✓（本机已装 VS2022 构建工具）。若出现 Developer Mode / 符号链接报错，提示用户运行 `start ms-settings:developers` 打开开发者模式后重试。

- [ ] **Step 3: 创建项目并添加依赖**

```bash
cd /d/projects/ops-center/easy_tunnel
flutter create --project-name easy_tunnel --org dev.easytunnel --platforms=windows app
cd app
flutter pub add provider window_manager tray_manager uuid path_provider local_notifier path
```

- [ ] **Step 4: 配置托盘图标资产**

```bash
cd /d/projects/ops-center/easy_tunnel/app
mkdir -p assets
cp windows/runner/resources/app_icon.ico assets/tray_icon.ico
```

修改 `pubspec.yaml`，在 `flutter:` 节点下（`uses-material-design: true` 之后）追加：

```yaml
  assets:
    - assets/
```

- [ ] **Step 5: 删除默认示例测试并验证工程可编译**

```bash
cd /d/projects/ops-center/easy_tunnel/app
rm test/widget_test.dart
flutter analyze
flutter build windows --debug
```

Expected: analyze 零告警；`build\windows\x64\runner\Debug\easy_tunnel.exe` 生成。

- [ ] **Step 6: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app
git commit -m "feat(easy-tunnel): scaffold Flutter Windows app with dependencies

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 2: 数据模型 TunnelModel（含 JSON 序列化）

**Files:**
- Create: `easy_tunnel/app/lib/models/tunnel_model.dart`
- Test: `easy_tunnel/app/test/tunnel_model_test.dart`

**Interfaces:**
- Produces（后续所有任务依赖，签名必须逐字一致）:
  - `enum TunnelStatus { stopped, starting, running, reconnecting, error }`
  - `class TunnelModel` 字段：`final String id; String name; int targetPort; String? dockerContainerName; String provider; String mode; String? customDomain; String? token; TunnelStatus status; String? publicUrl; int? processPid; String? lastError; final List<String> logs;`
  - `TunnelModel({required id, required name, required targetPort, dockerContainerName, provider='cloudflare', mode='quick', customDomain, token, status=stopped, publicUrl, processPid, lastError, List<String>? logs})`
  - `TunnelModel copyWith({String? token, String? name, int? targetPort, String? dockerContainerName, String? provider, String? mode, String? customDomain})`（仅复制配置字段，status/pid/logs 不复制）
  - `factory TunnelModel.fromJson(Map<String, dynamic>)` / `Map<String, dynamic> toJson()`
  - JSON 中 `status` 存储为 `status.name` 字符串；`logs` 不参与持久化。

- [ ] **Step 1: 写失败测试**

```dart
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
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter test test/tunnel_model_test.dart
```

Expected: FAIL（找不到 `package:easy_tunnel/models/tunnel_model.dart`）。

- [ ] **Step 3: 实现模型**

`lib/models/tunnel_model.dart`：

```dart
enum TunnelStatus { stopped, starting, running, reconnecting, error }

class TunnelModel {
  final String id;
  String name;
  int targetPort;
  String? dockerContainerName;
  String provider; // 'cloudflare' | 'ngrok'
  String mode; // 'quick' | 'custom'
  String? customDomain;
  String? token;
  TunnelStatus status;
  String? publicUrl;
  int? processPid;
  String? lastError;
  final List<String> logs;

  TunnelModel({
    required this.id,
    required this.name,
    required this.targetPort,
    this.dockerContainerName,
    this.provider = 'cloudflare',
    this.mode = 'quick',
    this.customDomain,
    this.token,
    this.status = TunnelStatus.stopped,
    this.publicUrl,
    this.processPid,
    this.lastError,
    List<String>? logs,
  }) : logs = logs ?? [];

  TunnelModel copyWith({
    String? name,
    int? targetPort,
    String? dockerContainerName,
    String? provider,
    String? mode,
    String? customDomain,
    String? token,
  }) {
    return TunnelModel(
      id: id,
      name: name ?? this.name,
      targetPort: targetPort ?? this.targetPort,
      dockerContainerName: dockerContainerName ?? this.dockerContainerName,
      provider: provider ?? this.provider,
      mode: mode ?? this.mode,
      customDomain: customDomain ?? this.customDomain,
      token: token ?? this.token,
    );
  }

  factory TunnelModel.fromJson(Map<String, dynamic> json) {
    return TunnelModel(
      id: json['id'] as String,
      name: json['name'] as String,
      targetPort: json['targetPort'] as int,
      dockerContainerName: json['dockerContainerName'] as String?,
      provider: (json['provider'] as String?) ?? 'cloudflare',
      mode: (json['mode'] as String?) ?? 'quick',
      customDomain: json['customDomain'] as String?,
      token: json['token'] as String?,
      status: TunnelStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => TunnelStatus.stopped,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetPort': targetPort,
        'dockerContainerName': dockerContainerName,
        'provider': provider,
        'mode': mode,
        'customDomain': customDomain,
        'token': token,
        'status': status.name,
      };
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/tunnel_model_test.dart
flutter analyze
```

Expected: 3 tests PASS，analyze 零告警。

- [ ] **Step 5: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/models/tunnel_model.dart easy_tunnel/app/test/tunnel_model_test.dart
git commit -m "feat(easy-tunnel): add TunnelModel with json serialization

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 3: 命令输出解析器（纯函数，核心 TDD 任务）

**Files:**
- Create: `easy_tunnel/app/lib/services/parsers.dart`
- Test: `easy_tunnel/app/test/parsers_test.dart`

**Interfaces:**
- Produces:
  - `class DockerContainer { final String id; final String name; final Set<int> hostPorts; final String status; const DockerContainer({required this.id, required this.name, required this.hostPorts, required this.status}); }`
  - `int? parseNetstatListeningPid(String output, int port)`
  - `String? parseTasklistName(String csvOutput)`
  - `List<DockerContainer> parseDockerPs(String output)`
  - `String? extractPublicUrl(String line)`（同时匹配 trycloudflare 与 ngrok 域名）
  - `bool looksLikeAuthError(String line)`

- [ ] **Step 1: 写失败测试**

`test/parsers_test.dart`：

```dart
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
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/parsers_test.dart
```

Expected: FAIL（找不到 parsers.dart）。

- [ ] **Step 3: 实现解析器**

`lib/services/parsers.dart`：

```dart
class DockerContainer {
  final String id;
  final String name;
  final Set<int> hostPorts;
  final String status;

  const DockerContainer({
    required this.id,
    required this.name,
    required this.hostPorts,
    required this.status,
  });

  String get label => hostPorts.isEmpty ? name : '$name:${hostPorts.first}';
}

/// 从 `netstat -ano -p tcp` 输出中找出处于 LISTENING 且监听 [port] 的 PID。
int? parseNetstatListeningPid(String output, int port) {
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (!line.startsWith('TCP')) continue;
    final cols = line.split(RegExp(r'\s+'));
    if (cols.length < 5) continue;
    if (cols[3] != 'LISTENING') continue;
    final local = cols[1];
    final sep = local.lastIndexOf(':');
    if (sep <= 0) continue;
    final localPort = int.tryParse(local.substring(sep + 1));
    if (localPort != port) continue;
    return int.tryParse(cols.last);
  }
  return null;
}

/// 从 `tasklist /FO CSV /NH` 输出中取第一行的进程名（第一个引号字段）。
String? parseTasklistName(String csvOutput) {
  for (final raw in csvOutput.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = RegExp(r'^"([^"]+)"').firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}

/// 解析 `docker ps --format "{{.ID}}|{{.Names}}|{{.Ports}}|{{.Status}}"` 输出。
List<DockerContainer> parseDockerPs(String output) {
  final result = <DockerContainer>[];
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split('|');
    if (parts.length < 4) continue;
    final ports = <int>{};
    for (final m in RegExp(r':(\d+)->').allMatches(parts[2])) {
      final p = int.tryParse(m.group(1)!);
      if (p != null) ports.add(p);
    }
    result.add(DockerContainer(
      id: parts[0],
      name: parts[1],
      hostPorts: ports,
      status: parts[3],
    ));
  }
  return result;
}

/// 从任意一行子进程输出中提取分配到的公网 URL。
String? extractPublicUrl(String line) {
  final cf = RegExp(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com').firstMatch(line);
  if (cf != null) return cf.group(0);
  final ng = RegExp(r'https://[a-zA-Z0-9.-]+\.ngrok(?:-free)?\.(?:app|dev)')
      .firstMatch(line);
  if (ng != null) return ng.group(0);
  return null;
}

/// 判断一行日志是否为认证/Token 错误。
bool looksLikeAuthError(String line) {
  final l = line.toLowerCase();
  return l.contains('authentication failed') ||
      l.contains('invalid token') ||
      l.contains('invalid authtoken') ||
      l.contains('err_ngrok_401') ||
      l.contains('unauthorized');
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/parsers_test.dart
flutter analyze
```

Expected: 全部 PASS，analyze 零告警。

- [ ] **Step 5: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/services/parsers.dart easy_tunnel/app/test/parsers_test.dart
git commit -m "feat(easy-tunnel): add output parsers for netstat/tasklist/docker/url

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 4: PortMonitorService（端口探测与一键强杀）

**Files:**
- Create: `easy_tunnel/app/lib/services/port_monitor_service.dart`
- Test: `easy_tunnel/app/test/port_monitor_service_test.dart`

**Interfaces:**
- Consumes: `parseNetstatListeningPid`、`parseTasklistName`（Task 3）
- Produces:
  - `typedef CommandRunner = Future<ProcessResult> Function(String executable, List<String> arguments);`
  - `class PortStatus { final int port; final bool inUse; final int? pid; final String? processName; const PortStatus({required this.port, required this.inUse, this.pid, this.processName}); }`
  - `class PortMonitorService { PortMonitorService({CommandRunner? runner}); Future<PortStatus> inspect(int port); Future<bool> killProcessTree(int pid); }`

- [ ] **Step 1: 写失败测试**

```dart
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
```

- [ ] **Step 2: 运行确认失败**

```bash
flutter test test/port_monitor_service_test.dart
```

Expected: FAIL（文件不存在）。

- [ ] **Step 3: 实现服务**

`lib/services/port_monitor_service.dart`：

```dart
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
}
```

- [ ] **Step 4: 运行确认通过**

```bash
flutter test test/port_monitor_service_test.dart
flutter analyze
```

Expected: 3 tests PASS。

- [ ] **Step 5: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/services/port_monitor_service.dart easy_tunnel/app/test/port_monitor_service_test.dart
git commit -m "feat(easy-tunnel): add port monitor service with kill support

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 5: DockerService（容器扫描，失败降级为空列表）

**Files:**
- Create: `easy_tunnel/app/lib/services/docker_service.dart`
- Test: `easy_tunnel/app/test/docker_service_test.dart`

**Interfaces:**
- Consumes: `parseDockerPs`、`DockerContainer`（Task 3）、`CommandRunner`（Task 4）
- Produces: `class DockerService { DockerService({CommandRunner? runner}); Future<List<DockerContainer>> listContainers(); }`

- [ ] **Step 1: 写失败测试**

```dart
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
```

- [ ] **Step 2: 运行确认失败**

```bash
flutter test test/docker_service_test.dart
```

- [ ] **Step 3: 实现服务**

`lib/services/docker_service.dart`：

```dart
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
```

- [ ] **Step 4: 运行确认通过**

```bash
flutter test test/docker_service_test.dart
flutter analyze
```

- [ ] **Step 5: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/services/docker_service.dart easy_tunnel/app/test/docker_service_test.dart
git commit -m "feat(easy-tunnel): add docker container discovery service

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 6: TunnelEngine（命令构建 + 子进程拉起/停止）

**Files:**
- Create: `easy_tunnel/app/lib/services/tunnel_engine.dart`
- Test: `easy_tunnel/app/test/tunnel_engine_test.dart`

**Interfaces:**
- Consumes: `TunnelModel`（Task 2）、`extractPublicUrl`/`looksLikeAuthError`（Task 3）
- Produces:
  - `class TunnelInvocation { final String executable; final List<String> arguments; const TunnelInvocation({required this.executable, required this.arguments}); }`
  - `static TunnelInvocation TunnelEngine.buildInvocation(TunnelModel tunnel, {required String cloudflaredPath, required String ngrokPath})`
  - `Future<Process> TunnelEngine.start(TunnelModel tunnel, {required String cloudflaredPath, required String ngrokPath, required void Function(String line) onLine, required void Function(String url) onUrl})`
  - `Future<void> TunnelEngine.stop(int pid)`

命令规则（必须逐字实现）：
- cloudflare + quick：`<cloudflared> tunnel --url http://127.0.0.1:<port> --no-autoupdate`
- cloudflare + custom（有 token）：`<cloudflared> tunnel run --token <token>`
- ngrok：`<ngrok> http 127.0.0.1:<port> --log stdout`，有 token 追加 `--authtoken <token>`，custom 模式且有域名追加 `--domain <domain>`

- [ ] **Step 1: 写失败测试**

```dart
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
```

- [ ] **Step 2: 运行确认失败**

```bash
flutter test test/tunnel_engine_test.dart
```

- [ ] **Step 3: 实现引擎**

`lib/services/tunnel_engine.dart`：

```dart
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
```

- [ ] **Step 4: 运行确认通过**

```bash
flutter test test/tunnel_engine_test.dart
flutter analyze
```

- [ ] **Step 5: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/services/tunnel_engine.dart easy_tunnel/app/test/tunnel_engine_test.dart
git commit -m "feat(easy-tunnel): add tunnel process engine

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

### Task 7: DependencyService（二进制探测与自动下载）

**Files:**
- Create: `easy_tunnel/app/lib/services/dependency_service.dart`

**Interfaces:**
- Produces:
  - `class DependencyService { DependencyService(Directory binDir); static Future<DependencyService> create(); String get cloudflaredPath; String get ngrokPath; Future<String> resolveCloudflared(); Future<String> resolveNgrok(); Future<void> ensureCloudflared({void Function(double progress)? onProgress}); Future<void> ensureNgrok({void Function(double progress)? onProgress}); }`
  - `create()` 使用 `getApplicationSupportDirectory()` 下的 `bin/` 目录。
  - `resolve*()` 优先 `where` 查找 PATH 中已安装版本，否则确保下载到本地 `bin/` 并返回本地路径。
  - 下载源：`https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe`；`https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip`（用系统 `tar -xf` 解压）。

本任务无单元测试（网络下载与系统环境交互），由 Task 16 手动验证覆盖。

- [ ] **Step 1: 实现服务**

`lib/services/dependency_service.dart`：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DependencyService {
  final Directory binDir;

  DependencyService(this.binDir);

  static Future<DependencyService> create() async {
    final support = await getApplicationSupportDirectory();
    final bin = Directory(p.join(support.path, 'bin'));
    await bin.create(recursive: true);
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

  Future<void> ensureCloudflared({void Function(double)? onProgress}) async {
    final target = File(cloudflaredPath);
    if (await target.exists()) return;
    await _download(
      Uri.parse(
          'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'),
      target,
      onProgress,
    );
  }

  Future<void> ensureNgrok({void Function(double)? onProgress}) async {
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
      throw Exception('ngrok 解压失败');
    }
  }

  Future<void> _download(
    Uri url,
    File target,
    void Function(double)? onProgress,
  ) async {
    await binDir.create(recursive: true);
    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) {
        throw HttpException('下载失败 HTTP ${resp.statusCode}: $url');
      }
      final sink = target.openWrite();
      final total = resp.contentLength;
      var received = 0;
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }
}
```

- [ ] **Step 2: 编译验证**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter analyze
```

Expected: 零告警。

- [ ] **Step 3: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/services/dependency_service.dart
git commit -m "feat(easy-tunnel): add dependency download service

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 8: StorageService（配置持久化）

**Files:**
- Create: `easy_tunnel/app/lib/services/storage_service.dart`
- Test: `easy_tunnel/app/test/storage_service_test.dart`

**Interfaces:**
- Consumes: `TunnelModel`（Task 2）
- Produces:
  - `class AppSettings { String cloudflareToken; String ngrokToken; bool detailedLogs; bool launchAtStartup; bool closeToTray; AppSettings({...默认值}); fromJson/toJson }`
  - `class AppConfig { List<TunnelModel> tunnels; AppSettings settings; AppConfig({...}); fromJson/toJson }`
  - `class StorageService { StorageService(File file); static Future<StorageService> create(); Future<AppConfig> load(); Future<void> save(AppConfig config); }`
  - 默认值：`cloudflareToken=''`、`ngrokToken=''`、`detailedLogs=true`、`launchAtStartup=false`、`closeToTray=true`。
  - `load()` 文件不存在或 JSON 损坏时返回默认 `AppConfig()`，不得抛异常。

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/models/tunnel_model.dart';
import 'package:easy_tunnel/services/storage_service.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('easy_tunnel_test');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('save 后 load 还原配置', () async {
    final file = File('${tmp.path}/config.json');
    final svc = StorageService(file);
    final cfg = AppConfig(
      tunnels: [TunnelModel(id: 'a', name: 'web', targetPort: 8080)],
      settings: AppSettings(cloudflareToken: 'CF', ngrokToken: 'NG'),
    );
    await svc.save(cfg);
    final loaded = await svc.load();
    expect(loaded.tunnels.single.id, 'a');
    expect(loaded.settings.cloudflareToken, 'CF');
    expect(loaded.settings.ngrokToken, 'NG');
    expect(loaded.settings.closeToTray, isTrue);
  });

  test('文件不存在时返回默认配置', () async {
    final svc = StorageService(File('${tmp.path}/none.json'));
    final cfg = await svc.load();
    expect(cfg.tunnels, isEmpty);
    expect(cfg.settings.detailedLogs, isTrue);
  });

  test('JSON 损坏时返回默认配置', () async {
    final file = File('${tmp.path}/bad.json');
    await file.writeAsString('{not json');
    final cfg = await StorageService(file).load();
    expect(cfg.tunnels, isEmpty);
  });
}
```

- [ ] **Step 2: 运行确认失败**

```bash
flutter test test/storage_service_test.dart
```

- [ ] **Step 3: 实现服务**

`lib/services/storage_service.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tunnel_model.dart';

class AppSettings {
  String cloudflareToken;
  String ngrokToken;
  bool detailedLogs;
  bool launchAtStartup;
  bool closeToTray;

  AppSettings({
    this.cloudflareToken = '',
    this.ngrokToken = '',
    this.detailedLogs = true,
    this.launchAtStartup = false,
    this.closeToTray = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        cloudflareToken: (json['cloudflareToken'] as String?) ?? '',
        ngrokToken: (json['ngrokToken'] as String?) ?? '',
        detailedLogs: (json['detailedLogs'] as bool?) ?? true,
        launchAtStartup: (json['launchAtStartup'] as bool?) ?? false,
        closeToTray: (json['closeToTray'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
        'cloudflareToken': cloudflareToken,
        'ngrokToken': ngrokToken,
        'detailedLogs': detailedLogs,
        'launchAtStartup': launchAtStartup,
        'closeToTray': closeToTray,
      };
}

class AppConfig {
  List<TunnelModel> tunnels;
  AppSettings settings;

  AppConfig({List<TunnelModel>? tunnels, AppSettings? settings})
      : tunnels = tunnels ?? [],
        settings = settings ?? AppSettings();

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        tunnels: ((json['tunnels'] as List?) ?? [])
            .map((e) => TunnelModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        settings: AppSettings.fromJson(
            (json['settings'] as Map<String, dynamic>?) ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'tunnels': tunnels.map((t) => t.toJson()).toList(),
        'settings': settings.toJson(),
      };
}

class StorageService {
  final File file;

  StorageService(this.file);

  static Future<StorageService> create() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return StorageService(File(p.join(dir.path, 'config.json')));
  }

  Future<AppConfig> load() async {
    try {
      if (!await file.exists()) return AppConfig();
      final text = await file.readAsString();
      final json = jsonDecode(text) as Map<String, dynamic>;
      return AppConfig.fromJson(json);
    } catch (_) {
      return AppConfig();
    }
  }

  Future<void> save(AppConfig config) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config.toJson()));
  }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
flutter test test/storage_service_test.dart
flutter analyze
```

- [ ] **Step 5: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/services/storage_service.dart easy_tunnel/app/test/storage_service_test.dart
git commit -m "feat(easy-tunnel): add config persistence service

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 9: TunnelProvider（状态编排核心）

**Files:**
- Create: `easy_tunnel/app/lib/providers/tunnel_provider.dart`
- Test: `easy_tunnel/app/test/tunnel_provider_test.dart`

**Interfaces:**
- Consumes: Task 2–8 全部服务。
- Produces（UI 任务依赖的公开 API，签名逐字一致）:
  - `class TunnelProvider extends ChangeNotifier`
  - 构造：`TunnelProvider({required StorageService storage, required DependencyService deps, PortMonitorService? portMonitor, DockerService? docker, TunnelEngine? engine, void Function(String title, String body)? notify})`
  - `static Future<TunnelProvider> bootstrap({void Function(String, String)? notify})`
  - 字段（getter）：`List<TunnelModel> tunnels`、`AppSettings settings`、`List<DockerContainer> dockerContainers`、`Map<String, PortStatus> portStatuses`、`int currentTab`（0 概览 / 1 隧道管理 / 2 设置，setter 会 notify）、`String? selectedLogTunnelId`、`bool cloudflaredReady`、`bool ngrokReady`、`int eventsToday`
  - 方法：`Future<void> init()`、`TunnelModel? tunnelById(String id)`、`Future<void> addTunnel(TunnelModel t)`、`Future<void> updateTunnel(TunnelModel t)`、`Future<void> removeTunnel(String id)`、`Future<void> startTunnel(String id)`、`Future<void> stopTunnel(String id)`、`Future<void> killOccupant(String id)`、`Future<void> inspectAllPorts()`、`Future<PortStatus> inspectPort(int port)`、`Future<void> refreshDocker()`、`Future<void> stopAll()`、`Future<void> saveSettings()`、`bool isOrphanOccupied(TunnelModel t)`、`int get conflictCount`
  - 行为约定：
    - 启动时若隧道自身 token 为空，回退使用 `settings.cloudflareToken` / `settings.ngrokToken`。
    - 日志追加到 `tunnel.logs`，超过 200 行裁剪头部；`settings.detailedLogs == false` 时只记录启动/错误/URL 三类行。
    - 捕获 URL 时置 `running` 并触发 `notify('隧道已上线', url)`。
    - 识别认证错误时置 `error`、写 `lastError`、触发通知。
    - 非手动停止的进程退出：置 `reconnecting` 并按 2s/4s/8s 指数退避重启，最多 3 次，超过置 `error`。
  - `isOrphanOccupied(t)` 定义：`t.status == TunnelStatus.stopped && portStatuses[t.id]?.inUse == true`（停止状态但端口被占 → 疑似僵尸进程）。

- [ ] **Step 1: 写失败测试（只测不依赖真实进程的行为）**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/models/tunnel_model.dart';
import 'package:easy_tunnel/providers/tunnel_provider.dart';
import 'package:easy_tunnel/services/dependency_service.dart';
import 'package:easy_tunnel/services/docker_service.dart';
import 'package:easy_tunnel/services/port_monitor_service.dart';
import 'package:easy_tunnel/services/storage_service.dart';

class _FakeStorage extends StorageService {
  AppConfig stored = AppConfig();
  _FakeStorage() : super(File('unused.json'));

  @override
  Future<AppConfig> load() async => stored;

  @override
  Future<void> save(AppConfig config) async {
    stored = config;
  }
}

void main() {
  late _FakeStorage storage;
  late TunnelProvider provider;

  setUp(() {
    storage = _FakeStorage();
    provider = TunnelProvider(
      storage: storage,
      deps: DependencyService(Directory.systemTemp),
      portMonitor: PortMonitorServiceStub(),
      docker: DockerServiceStub(),
    );
  });

  test('addTunnel 持久化并可查询', () async {
    await provider.addTunnel(
        TunnelModel(id: 'a', name: 'web', targetPort: 8080));
    expect(provider.tunnels.length, 1);
    expect(provider.tunnelById('a')?.name, 'web');
    expect(storage.stored.tunnels.length, 1);
  });

  test('removeTunnel 删除并持久化', () async {
    await provider.addTunnel(
        TunnelModel(id: 'a', name: 'web', targetPort: 8080));
    await provider.removeTunnel('a');
    expect(provider.tunnels, isEmpty);
    expect(storage.stored.tunnels, isEmpty);
  });

  test('conflictCount 统计“已停止但端口被占用”的隧道', () async {
    await provider.addTunnel(
        TunnelModel(id: 'a', name: 'web', targetPort: 8080));
    provider.portStatuses['a'] = const PortStatus(
        port: 8080, inUse: true, pid: 1, processName: 'node.exe');
    expect(provider.conflictCount, 1);
    provider.tunnels.first.status = TunnelStatus.running;
    expect(provider.conflictCount, 0);
  });
}
```

测试桩（放在测试文件底部，顶层声明可被上方 setUp 引用）：

```dart
class PortMonitorServiceStub extends PortMonitorService {
  PortMonitorServiceStub()
      : super(runner: (e, a) async => ProcessResult(0, 0, '', ''));
}

class DockerServiceStub extends DockerService {
  DockerServiceStub()
      : super(runner: (e, a) async => ProcessResult(0, 0, '', ''));
}
```

其中 `portStatuses` 的赋值直接使用 `PortStatus` 的 const 构造：

```dart
provider.portStatuses['a'] =
    const PortStatus(port: 8080, inUse: true, pid: 1, processName: 'node.exe');
```

- [ ] **Step 2: 运行确认失败**

```bash
flutter test test/tunnel_provider_test.dart
```

- [ ] **Step 3: 实现 Provider**

`lib/providers/tunnel_provider.dart`（完整实现）：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/tunnel_model.dart';
import '../services/dependency_service.dart';
import '../services/docker_service.dart';
import '../services/parsers.dart';
import '../services/port_monitor_service.dart';
import '../services/storage_service.dart';
import '../services/tunnel_engine.dart';

class TunnelProvider extends ChangeNotifier {
  final StorageService storage;
  final DependencyService deps;
  final PortMonitorService portMonitor;
  final DockerService docker;
  final TunnelEngine engine;
  final void Function(String title, String body) _notify;

  List<TunnelModel> tunnels = [];
  AppSettings settings = AppSettings();
  List<DockerContainer> dockerContainers = [];
  Map<String, PortStatus> portStatuses = {};
  int eventsToday = 0;
  bool cloudflaredReady = false;
  bool ngrokReady = false;

  int _currentTab = 0;
  int get currentTab => _currentTab;
  set currentTab(int v) {
    _currentTab = v;
    notifyListeners();
  }

  String? selectedLogTunnelId;

  final Map<String, Process> _processes = {};
  final Set<String> _manualStop = {};
  final Map<String, int> _retryCount = {};
  Timer? _inspectTimer;
  Timer? _dockerTimer;
  bool _disposed = false;

  TunnelProvider({
    required this.storage,
    required this.deps,
    PortMonitorService? portMonitor,
    DockerService? docker,
    TunnelEngine? engine,
    void Function(String title, String body)? notify,
  })  : portMonitor = portMonitor ?? PortMonitorService(),
        docker = docker ?? DockerService(),
        engine = engine ?? TunnelEngine(),
        _notify = notify ?? _noop;

  static void _noop(String a, String b) {}

  static Future<TunnelProvider> bootstrap(
          {void Function(String, String)? notify}) async =>
      TunnelProvider(
        storage: await StorageService.create(),
        deps: await DependencyService.create(),
        notify: notify,
      );

  Future<void> init() async {
    final config = await storage.load();
    settings = config.settings;
    for (final t in config.tunnels) {
      t.status = TunnelStatus.stopped;
      t.processPid = null;
      t.logs.clear();
    }
    tunnels = config.tunnels;
    _inspectTimer = Timer.periodic(
        const Duration(seconds: 6), (_) => inspectAllPorts());
    _dockerTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => refreshDocker());
    unawaited(_prepareDependencies());
    unawaited(refreshDocker());
    await inspectAllPorts();
    notifyListeners();
  }

  Future<void> _prepareDependencies() async {
    try {
      await deps.ensureCloudflared();
      cloudflaredReady = true;
    } catch (_) {
      cloudflaredReady = false;
    }
    try {
      await deps.ensureNgrok();
      ngrokReady = true;
    } catch (_) {
      ngrokReady = false;
    }
    notifyListeners();
  }

  TunnelModel? tunnelById(String id) {
    for (final t in tunnels) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool isOrphanOccupied(TunnelModel t) =>
      t.status == TunnelStatus.stopped &&
      (portStatuses[t.id]?.inUse ?? false);

  int get conflictCount => tunnels.where(isOrphanOccupied).length;

  Future<void> _persist() =>
      storage.save(AppConfig(tunnels: tunnels, settings: settings));

  Future<void> addTunnel(TunnelModel t) async {
    tunnels.add(t);
    await _persist();
    notifyListeners();
    unawaited(_inspectOne(t));
  }

  Future<void> updateTunnel(TunnelModel t) async {
    final i = tunnels.indexWhere((x) => x.id == t.id);
    if (i >= 0) tunnels[i] = t;
    await _persist();
    notifyListeners();
  }

  Future<void> removeTunnel(String id) async {
    await stopTunnel(id);
    tunnels.removeWhere((t) => t.id == id);
    portStatuses.remove(id);
    if (selectedLogTunnelId == id) selectedLogTunnelId = null;
    await _persist();
    notifyListeners();
  }

  Future<PortStatus> inspectPort(int port) => portMonitor.inspect(port);

  Future<void> _inspectOne(TunnelModel t) async {
    try {
      portStatuses[t.id] = await portMonitor.inspect(t.targetPort);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> inspectAllPorts() async {
    for (final t in tunnels) {
      await _inspectOne(t);
    }
  }

  Future<void> refreshDocker() async {
    dockerContainers = await docker.listContainers();
    notifyListeners();
  }

  String _resolveToken(TunnelModel t) {
    if (t.token != null && t.token!.isNotEmpty) return t.token!;
    return t.provider == 'cloudflare'
        ? settings.cloudflareToken
        : settings.ngrokToken;
  }

  void _appendLog(TunnelModel t, String line) {
    final important = line.contains('ERR') ||
        line.contains('error') ||
        line.contains('failed') ||
        line.contains('Your quick Tunnel') ||
        line.contains('started tunnel') ||
        extractPublicUrl(line) != null;
    if (!settings.detailedLogs && !important) return;
    t.logs.add(line);
    if (t.logs.length > 200) {
      t.logs.removeRange(0, t.logs.length - 200);
    }
  }

  Future<void> startTunnel(String id) async {
    final t = tunnelById(id);
    if (t == null) return;
    if (t.status == TunnelStatus.running ||
        t.status == TunnelStatus.starting) {
      return;
    }
    _manualStop.remove(id);
    _retryCount[id] = 0;
    t.status = TunnelStatus.starting;
    t.publicUrl = null;
    t.lastError = null;
    t.logs.clear();
    notifyListeners();

    try {
      final String exe;
      if (t.provider == 'cloudflare') {
        exe = await deps.resolveCloudflared();
      } else {
        exe = await deps.resolveNgrok();
      }
      final token = _resolveToken(t);
      final effective = t.copyWith(token: token.isEmpty ? null : token);

      final process = await engine.start(
        effective,
        cloudflaredPath: t.provider == 'cloudflare' ? exe : deps.cloudflaredPath,
        ngrokPath: t.provider == 'ngrok' ? exe : deps.ngrokPath,
        onLine: (line) {
          _appendLog(t, line);
          if (looksLikeAuthError(line)) {
            t.status = TunnelStatus.error;
            t.lastError = '认证失败，请检查 Token 配置';
            _notify('认证失败', '${t.name}: 请检查 Token 配置');
          }
          notifyListeners();
        },
        onUrl: (url) {
          t.status = TunnelStatus.running;
          t.publicUrl = url;
          _retryCount[id] = 0;
          eventsToday += 1;
          _notify('隧道已上线', '${t.name}\n$url');
          notifyListeners();
        },
      );
      _processes[id] = process;
      t.processPid = process.pid;
      process.exitCode.then((code) => _onProcessExit(id, code));
      notifyListeners();
    } catch (e) {
      t.status = TunnelStatus.error;
      t.lastError = '$e';
      notifyListeners();
      _notify('隧道启动失败', '${t.name}: $e');
    }
  }

  void _onProcessExit(String id, int code) {
    final t = tunnelById(id);
    if (t == null) return;
    _processes.remove(id);
    t.processPid = null;
    if (_manualStop.contains(id)) {
      t.status = TunnelStatus.stopped;
      notifyListeners();
      return;
    }
    final attempt = (_retryCount[id] ?? 0) + 1;
    _retryCount[id] = attempt;
    if (attempt > 3) {
      t.status = TunnelStatus.error;
      t.lastError = '进程异常退出 (exit $code)，重试 3 次失败';
      notifyListeners();
      _notify('隧道异常退出', '${t.name}: exit code $code');
      return;
    }
    t.status = TunnelStatus.reconnecting;
    notifyListeners();
    Timer(Duration(seconds: 1 << attempt), () {
      if (_manualStop.contains(id)) return;
      if (tunnelById(id)?.status == TunnelStatus.reconnecting) {
        startTunnel(id);
      }
    });
  }

  Future<void> stopTunnel(String id) async {
    _manualStop.add(id);
    _retryCount[id] = 0;
    final t = tunnelById(id);
    final pid = t?.processPid;
    if (pid != null) {
      await engine.stop(pid);
    }
    _processes.remove(id);
    if (t != null) {
      t.status = TunnelStatus.stopped;
      t.processPid = null;
      t.publicUrl = null;
    }
    notifyListeners();
  }

  Future<void> killOccupant(String id) async {
    final status = portStatuses[id];
    if (status?.pid == null) return;
    final ok = await portMonitor.killProcessTree(status!.pid!);
    if (ok) {
      eventsToday += 1;
      _notify('端口已释放',
          '已终止 ${status.processName ?? '进程'} (PID ${status.pid})');
    }
    await _inspectOne(tunnelById(id)!);
  }

  Future<void> stopAll() async {
    for (final t in List.of(tunnels)) {
      await stopTunnel(t.id);
    }
  }

  Future<void> saveSettings() async {
    await _persist();
    notifyListeners();
  }

  /// 供 UI 层清空某条隧道日志（notifyListeners 是 @protected，外部不可直接调用）。
  void clearLogs(String id) {
    tunnelById(id)?.logs.clear();
    notifyListeners();
  }

  /// 供设置页重新检测/下载依赖。
  Future<void> recheckDependencies() => _prepareDependencies();

  String newId() => const Uuid().v4();

  @override
  void dispose() {
    _disposed = true;
    _inspectTimer?.cancel();
    _dockerTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
flutter test test/tunnel_provider_test.dart
flutter analyze
```

Expected: 3 tests PASS。

- [ ] **Step 5: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/providers/tunnel_provider.dart easy_tunnel/app/test/tunnel_provider_test.dart
git commit -m "feat(easy-tunnel): add tunnel state provider

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 10: 主题、入口、应用外壳、托盘与窗口服务

**Files:**
- Create: `easy_tunnel/app/lib/theme.dart`
- Create: `easy_tunnel/app/lib/services/tray_window_service.dart`
- Create: `easy_tunnel/app/lib/ui/title_bar.dart`
- Create: `easy_tunnel/app/lib/app.dart`
- Modify: `easy_tunnel/app/lib/main.dart`（整体替换默认 counter 示例）

**Interfaces:**
- Consumes: `TunnelProvider`（Task 9）
- Produces:
  - `class AppColors`（静态常量，色值见全局约束）
  - `ThemeData buildTheme()`
  - `class TrayWindowService { TrayWindowService({required bool Function() shouldHideOnClose, required void Function() onShowApp, required void Function() onStopAll, required Future<void> Function() onExit}); Future<void> init(); Future<void> disposeService(); }`
  - `class TitleBar extends StatelessWidget`（自定义拖动标题栏）
  - `class EasyTunnelApp extends StatefulWidget { final TunnelProvider provider; }`
  - `class AppShell extends StatefulWidget`（标题栏 + 侧边栏 + 内容区 + 日志抽屉）
  - 暂时用占位内容渲染三个页面（首页/隧道页/设置页在后续任务中替换）：
    - `lib/ui/dashboard_page.dart`、`lib/ui/tunnels_page.dart`、`lib/ui/settings_page.dart`、`lib/ui/widgets/log_drawer.dart` 在本任务中先创建**最小占位实现**（中心 Text），后续任务替换为完整实现。

- [ ] **Step 1: 实现主题**

`lib/theme.dart`：

```dart
import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0D0F12);
  static const sidebar = Color(0xFF121418);
  static const card = Color(0xFF16191F);
  static const border = Color(0xFF21252F);
  static const borderLight = Color(0xFF2C3340);
  static const textMain = Color(0xFFEDEDED);
  static const textSub = Color(0xFF8A93A5);
  static const textMuted = Color(0xFF525A6B);
  static const green = Color(0xFF10B981);
  static const blue = Color(0xFF3B82F6);
  static const amber = Color(0xFFF59E0B);
  static const sky = Color(0xFF38BDF8);
  static const red = Color(0xFFEF4444);
  static const indigo = Color(0xFF818CF8);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Microsoft YaHei UI',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.blue,
      secondary: AppColors.green,
      surface: AppColors.card,
      error: AppColors.red,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(color: AppColors.textMain, fontSize: 12),
    ),
  );
}
```

- [ ] **Step 2: 实现托盘与窗口服务**

`lib/services/tray_window_service.dart`：

```dart
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayWindowService with TrayListener, WindowListener {
  final bool Function() shouldHideOnClose;
  final void Function() onShowApp;
  final void Function() onStopAll;
  final Future<void> Function() onExit;

  TrayWindowService({
    required this.shouldHideOnClose,
    required this.onShowApp,
    required this.onStopAll,
    required this.onExit,
  });

  Future<void> init() async {
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('Easy Tunnel 助手');
    final menu = Menu(items: [
      MenuItem(key: 'show', label: '打开主界面'),
      MenuItem.separator(),
      MenuItem(key: 'stop_all', label: '停止全部隧道'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: '彻底退出'),
    ]);
    await trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  Future<void> disposeService() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
  }

  @override
  void onTrayIconMouseDown() => onShowApp();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onShowApp();
      case 'stop_all':
        onStopAll();
      case 'exit':
        onExit();
    }
  }

  @override
  void onWindowClose() async {
    if (shouldHideOnClose()) {
      await windowManager.hide();
    } else {
      await onExit();
    }
  }
}
```

- [ ] **Step 3: 实现标题栏**

`lib/ui/title_bar.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        color: AppColors.sidebar,
        padding: const EdgeInsets.only(left: 12, right: 0),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.green, Color(0xFF2DD4BF)],
                ),
              ),
              child: const Icon(Icons.bolt, size: 10, color: Colors.black),
            ),
            const SizedBox(width: 8),
            const Text('Easy Tunnel 助手',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain)),
            const SizedBox(width: 6),
            const Text('v1.0.1',
                style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Consolas',
                    color: AppColors.textMuted)),
            const Spacer(),
            _WindowButton(
              icon: Icons.remove,
              onTap: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: Icons.crop_square,
              iconSize: 12,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _WindowButton(
              icon: Icons.close,
              hoverColor: AppColors.red,
              onTap: () => windowManager.close(),
              active: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color? hoverColor;
  final bool active;

  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.iconSize = 14,
    this.hoverColor,
    this.active = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 44,
          height: 36,
          color: _hover
              ? (widget.hoverColor ?? const Color(0xFF1E222B))
              : Colors.transparent,
          child: Icon(widget.icon,
              size: widget.iconSize,
              color: _hover ? Colors.white : AppColors.textSub),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 实现应用外壳与占位页面**

`lib/ui/dashboard_page.dart`（占位，Task 11 替换）：

```dart
import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('概览（建设中）'));
}
```

`lib/ui/tunnels_page.dart`（占位，Task 12 替换）：

```dart
import 'package:flutter/material.dart';

class TunnelsPage extends StatelessWidget {
  const TunnelsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('隧道管理（建设中）'));
}
```

`lib/ui/settings_page.dart`（占位，Task 15 替换）：

```dart
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('设置（建设中）'));
}
```

`lib/ui/widgets/log_drawer.dart`（占位，Task 14 替换）：

```dart
import 'package:flutter/material.dart';

class LogDrawer extends StatelessWidget {
  const LogDrawer({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`lib/ui/sidebar.dart`（本任务实现基础导航，Task 11 会保持兼容）：

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/tunnel_provider.dart';
import '../theme.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    return Container(
      width: 224,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavItem(
            icon: Icons.show_chart,
            iconColor: AppColors.sky,
            label: '数据概览',
            active: provider.currentTab == 0,
            onTap: () => provider.currentTab = 0,
          ),
          _NavItem(
            icon: Icons.bar_chart,
            iconColor: AppColors.amber,
            label: '隧道管理',
            active: provider.currentTab == 1,
            onTap: () => provider.currentTab = 1,
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('穿透引擎配置',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted)),
          ),
          _EngineRow(
            icon: Icons.cloud,
            iconColor: AppColors.amber,
            name: 'Cloudflare',
            ready: provider.cloudflaredReady,
          ),
          _EngineRow(
            icon: Icons.view_in_ar,
            iconColor: AppColors.indigo,
            name: 'ngrok',
            ready: provider.ngrokReady,
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('设置',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted)),
          ),
          _NavItem(
            icon: Icons.extension,
            iconColor: const Color(0xFF22D3EE),
            label: '系统设置',
            active: provider.currentTab == 2,
            onTap: () => provider.currentTab = 2,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns, size: 14, color: AppColors.sky),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Docker 服务',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSub)),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text('${provider.dockerContainers.length}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'Consolas',
                        color: AppColors.green)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1E222B) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? AppColors.borderLight : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? Colors.white : AppColors.textSub,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final bool ready;

  const _EngineRow({
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSub)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: ready
                  ? AppColors.green.withValues(alpha: 0.12)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: ready
                    ? AppColors.green.withValues(alpha: 0.5)
                    : AppColors.border,
              ),
            ),
            child: Text(
              ready ? '已就绪' : '未就绪',
              style: TextStyle(
                  fontSize: 10,
                  color: ready ? AppColors.green : AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
```

`lib/app.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/tunnel_provider.dart';
import 'services/tray_window_service.dart';
import 'theme.dart';
import 'ui/dashboard_page.dart';
import 'ui/settings_page.dart';
import 'ui/sidebar.dart';
import 'ui/title_bar.dart';
import 'ui/tunnels_page.dart';
import 'ui/widgets/log_drawer.dart';

class EasyTunnelApp extends StatefulWidget {
  final TunnelProvider provider;

  const EasyTunnelApp({super.key, required this.provider});

  @override
  State<EasyTunnelApp> createState() => _EasyTunnelAppState();
}

class _EasyTunnelAppState extends State<EasyTunnelApp> {
  TrayWindowService? _tray;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _tray = TrayWindowService(
        shouldHideOnClose: () => widget.provider.settings.closeToTray,
        onShowApp: () async {
          await windowManager.show();
          await windowManager.focus();
        },
        onStopAll: () => widget.provider.stopAll(),
        onExit: _exitApp,
      );
      await _tray!.init();
    });
  }

  Future<void> _exitApp() async {
    await widget.provider.stopAll();
    await _tray?.disposeService();
    await windowManager.destroy();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: MaterialApp(
        title: 'Easy Tunnel 助手',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = context.select<TunnelProvider, int>((p) => p.currentTab);
    return Scaffold(
      body: Column(
        children: [
          const TitleBar(),
          Expanded(
            child: Row(
              children: [
                const Sidebar(),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.bg,
                      border: Border(
                          left: BorderSide(color: AppColors.border)),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: IndexedStack(
                            index: tab,
                            children: const [
                              DashboardPage(),
                              TunnelsPage(),
                              SettingsPage(),
                            ],
                          ),
                        ),
                        const LogDrawer(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 重写入口 main.dart**

`lib/main.dart`（整体替换）：

```dart
import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'providers/tunnel_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1180, 760),
    minimumSize: Size(980, 640),
    center: true,
    title: 'Easy Tunnel 助手',
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  try {
    await LocalNotifier.instance.setup(appName: 'Easy Tunnel');
  } catch (_) {}

  final provider = await TunnelProvider.bootstrap(
    notify: (title, body) async {
      try {
        final n = LocalNotification(
          identifier: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title,
          body: body,
        );
        await LocalNotifier.instance.notify(n);
      } catch (_) {}
    },
  );
  await provider.init();

  runApp(EasyTunnelApp(provider: provider));
}
```

- [ ] **Step 6: 编译与冒烟验证**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter analyze
flutter build windows --debug
```

Expected: 零告警；编译通过。

- [ ] **Step 7: 首次运行冒烟（手动）**

```bash
./build/windows/x64/runner/Debug/easy_tunnel.exe
```

Expected: 暗色窗口出现，左侧栏显示导航与两个引擎状态（首次运行会自动下载 cloudflared/ngrok，几秒后徽标变绿），标题栏可拖动，关闭窗口后缩到系统托盘。确认后从托盘右键退出。

- [ ] **Step 8: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/theme.dart easy_tunnel/app/lib/services/tray_window_service.dart easy_tunnel/app/lib/ui/title_bar.dart easy_tunnel/app/lib/ui/sidebar.dart easy_tunnel/app/lib/ui/dashboard_page.dart easy_tunnel/app/lib/ui/tunnels_page.dart easy_tunnel/app/lib/ui/settings_page.dart easy_tunnel/app/lib/ui/widgets/log_drawer.dart easy_tunnel/app/lib/app.dart easy_tunnel/app/lib/main.dart
git commit -m "feat(easy-tunnel): app shell with dark theme, tray and window management

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 11: 概览页（统计卡片 + 装饰图表）

**Files:**
- Create: `easy_tunnel/app/lib/ui/widgets/stat_card.dart`
- Create: `easy_tunnel/app/lib/ui/widgets/activity_chart.dart`
- Modify: `easy_tunnel/app/lib/ui/dashboard_page.dart`（整体替换占位实现）

**Interfaces:**
- Consumes: `TunnelProvider`（Task 9）、`AppColors`（Task 10）、`TunnelCard`（Task 12 会创建——本任务先在概览页仅渲染统计区与图表，隧道卡片列表在 Task 12 完成后回填：本任务中概览页底部放一个 `Column(children: [])` 的占位容器 `_tunnelListSlot`，Task 12 替换为真实卡片列表）
- Produces:
  - `class StatCard extends StatelessWidget { final String title; final String value; final String? subtitle; final String? footnote; final Widget? leading; final Color valueColor; ... }`
  - `class ActivityChart extends StatelessWidget`（装饰性堆叠柱状图 + 平均虚线 + 悬浮数据浮窗由静态数据驱动）

- [ ] **Step 1: 实现 StatCard**

`lib/ui/widgets/stat_card.dart`：

```dart
import 'package:flutter/material.dart';

import '../../theme.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final String? footnote;
  final Widget? leading;
  final Color valueColor;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.footnote,
    this.leading,
    this.valueColor = AppColors.textMain,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSub)),
              ),
              const Icon(Icons.help_outline,
                  size: 12, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Consolas',
                            color: valueColor)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSub)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (footnote != null)
            Text(footnote!,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class RingProgress extends StatelessWidget {
  final double value; // 0..1

  const RingProgress({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: CustomPaint(
        painter: _RingPainter(value),
        child: Center(
          child: Text(
            '${(value * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: 'Consolas',
                color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;

  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = AppColors.border;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = AppColors.green;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -1.5708, 6.2832 * value.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value;
}
```

- [ ] **Step 2: 实现装饰图表**

`lib/ui/widgets/activity_chart.dart`：

```dart
import 'package:flutter/material.dart';

import '../../theme.dart';

class ActivityChart extends StatelessWidget {
  const ActivityChart({super.key});

  static const _bgHeights = <double>[
    0.75, 0.68, 0.70, 0.65, 0.60, 0.55, 0.95, 0.65, 0.30, 1.0,
    0.70, 0.68, 0.62, 0.66, 0.58, 0.22, 0.65, 0.24, 0.62, 0.67,
    0.70, 0.72, 0.65, 0.68, 0.60,
  ];

  static const _active = <int>[6, 8, 9, 15, 17];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 70,
                  child: Row(
                    children: [
                      const Text('平均',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.amber)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 1,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.amber.withValues(alpha: 0.6),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(_bgHeights.length, (i) {
                    final isActive = _active.contains(i);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: isActive
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: 150 * _bgHeights[i] * 0.78,
                                    decoration: const BoxDecoration(
                                      color: AppColors.green,
                                      borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(2)),
                                    ),
                                  ),
                                  Container(
                                    height: 150 * _bgHeights[i] * 0.22,
                                    decoration: const BoxDecoration(
                                      color: AppColors.blue,
                                    ),
                                  ),
                                ],
                              )
                            : Container(
                                height: 150 * _bgHeights[i],
                                decoration: BoxDecoration(
                                  color: const Color(0xFF212632),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                      ),
                    );
                  }),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    width: 200,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xF2121418),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('10/21 (今日高峰)',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        SizedBox(height: 4),
                        _TooltipRow('总穿透请求', '47.2k', AppColors.textMain),
                        _TooltipRow('直连调用', '4.7k', AppColors.sky),
                        _TooltipRow('边缘缓存命中', '42.5k', AppColors.green),
                        _TooltipRow('下行响应', '38.3 MB', AppColors.amber),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _AxisLabel('10/13'), _AxisLabel('10/16'), _AxisLabel('10/19'),
              _AxisLabel('10/22'), _AxisLabel('周日'), _AxisLabel('10/28'),
              _AxisLabel('周六'), _AxisLabel('11/3'), _AxisLabel('11/6'),
              _AxisLabel('11/9'), _AxisLabel('11/12'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  final String text;

  const _AxisLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          fontFamily: 'Consolas',
          color: AppColors.textMuted));
}

class _TooltipRow extends StatelessWidget {
  final String label;
  final String value;
  final Color dotColor;

  const _TooltipRow(this.label, this.value, this.dotColor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 9, color: AppColors.textSub)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 9,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: 实现概览页**

`lib/ui/dashboard_page.dart`（整体替换占位实现）：

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tunnel_model.dart';
import '../providers/tunnel_provider.dart';
import '../theme.dart';
import 'widgets/activity_chart.dart';
import 'widgets/stat_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final total = provider.tunnels.length;
    final running = provider.tunnels
        .where((t) => t.status == TunnelStatus.running)
        .length;
    final rate = total == 0 ? 0.0 : running / total;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('概览',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: [
                    _TimeChip('近1小时'),
                    _TimeChip('近1自然日'),
                    _TimeChip('近10分钟'),
                    _TimeChip('近一周'),
                    _TimeChip('近一个月', active: true),
                    _TimeChip('自定义'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const ActivityChart(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: StatCard(
                  title: '隧道在线率',
                  value: '$running / $total',
                  subtitle: '活跃隧道',
                  footnote: 'Cloudflare ${provider.cloudflaredReady ? "已就绪" : "未就绪"} · ngrok ${provider.ngrokReady ? "已就绪" : "未就绪"}',
                  leading: RingProgress(value: rate),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: '本地端口冲突',
                  value: '${provider.conflictCount}',
                  valueColor: provider.conflictCount > 0
                      ? AppColors.amber
                      : AppColors.textMain,
                  subtitle: provider.conflictCount > 0
                      ? '已停止隧道仍占用端口，可一键强杀'
                      : '暂无冲突',
                  footnote: '每 6 秒自动巡检一次',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: '今日启动事件',
                  value: '${provider.eventsToday}',
                  subtitle: '隧道上线 / 端口释放',
                  footnote: 'Docker 容器 ${provider.dockerContainers.length} 个在线',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: '已配置隧道',
                  value: '$total',
                  subtitle: '多隧道并发管理',
                  footnote: '停止 $total - $running 个',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final bool active;

  const _TimeChip(this.label, {this.active = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF2A2F3A) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? Colors.white : AppColors.textSub)),
    );
  }
}
```

- [ ] **Step 4: 编译验证**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter analyze
flutter build windows --debug
```

- [ ] **Step 5: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/ui/widgets/stat_card.dart easy_tunnel/app/lib/ui/widgets/activity_chart.dart easy_tunnel/app/lib/ui/dashboard_page.dart
git commit -m "feat(easy-tunnel): dashboard page with stat cards and chart

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 12: 隧道卡片组件 + 隧道管理页 + 概览页回填

**Files:**
- Create: `easy_tunnel/app/lib/ui/widgets/tunnel_card.dart`
- Modify: `easy_tunnel/app/lib/ui/tunnels_page.dart`（整体替换占位实现）
- Modify: `easy_tunnel/app/lib/ui/dashboard_page.dart`（在统计区之后插入隧道卡片列表）

**Interfaces:**
- Consumes: `TunnelProvider`（Task 9）、`PortStatus`（Task 4）、`AppColors`（Task 10）
- Produces: `class TunnelCard extends StatelessWidget { final TunnelModel tunnel; const TunnelCard({super.key, required this.tunnel}); }`
- 卡片行为（与设计文档一致）：
  - 状态徽标：running 绿色脉冲点 / starting 蓝色 / reconnecting 琥珀色 / error 红色 / stopped 灰色。
  - 端口健康文案规则见 Task 9 的 `isOrphanOccupied`：
    - running 且端口被监听 → 绿色「端口监听正常」
    - running 且端口未监听 → 灰色「端口暂无服务响应」
    - stopped 且端口被占用 → 琥珀色告警 + 显示 `进程名 (PID)` + 【一键强杀释放端口】按钮（调用 `provider.killOccupant(tunnel.id)`）
    - stopped 且端口空闲 → 灰色「端口空闲」
  - URL 栏：有 `publicUrl` 时显示链接 + 【复制】（`Clipboard.setData`）+【打开】（`Process.run('cmd', ['/c', 'start', '', url])`）。
  - 【实时日志】按钮：`provider.selectedLogTunnelId = tunnel.id`。
  - 启动/停止按钮：根据 status 切换，调用 `startTunnel` / `stopTunnel`。
  - 删除按钮：确认弹窗后 `removeTunnel`。

- [ ] **Step 1: 实现 TunnelCard**

`lib/ui/widgets/tunnel_card.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/tunnel_model.dart';
import '../../providers/tunnel_provider.dart';
import '../../theme.dart';

class TunnelCard extends StatelessWidget {
  final TunnelModel tunnel;

  const TunnelCard({super.key, required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final portStatus = provider.portStatuses[tunnel.id];
    final orphan = provider.isOrphanOccupied(tunnel);

    final borderColor = orphan
        ? AppColors.amber.withValues(alpha: 0.5)
        : AppColors.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tunnel.name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(width: 10),
              _ProviderBadge(provider: tunnel.provider, mode: tunnel.mode),
              const SizedBox(width: 8),
              _StatusBadge(status: tunnel.status, pid: tunnel.processPid),
              if (tunnel.dockerContainerName != null) ...[
                const SizedBox(width: 8),
                _TagChip(
                  '容器: ${tunnel.dockerContainerName}',
                  color: AppColors.blue,
                ),
              ],
              const Spacer(),
              _ActionButton(
                icon: Icons.terminal,
                label: '实时日志',
                onTap: () => provider.selectedLogTunnelId = tunnel.id,
              ),
              const SizedBox(width: 8),
              _StartStopButton(tunnel: tunnel),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 16, color: AppColors.textSub),
                color: AppColors.card,
                onSelected: (v) async {
                  if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('删除隧道',
                            style: TextStyle(fontSize: 14)),
                        content: Text('确定删除「${tunnel.name}」吗？',
                            style: const TextStyle(fontSize: 12)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('删除',
                                style: TextStyle(color: AppColors.red)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await provider.removeTunnel(tunnel.id);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('删除隧道',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.red)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _PortChip('127.0.0.1:${tunnel.targetPort}'),
              const SizedBox(width: 12),
              _PortHealth(
                tunnel: tunnel,
                orphan: orphan,
                processName: portStatus?.processName,
                pid: portStatus?.pid,
              ),
            ],
          ),
          if (tunnel.publicUrl != null) ...[
            const SizedBox(height: 10),
            _UrlBar(url: tunnel.publicUrl!),
          ],
          if (tunnel.status == TunnelStatus.error &&
              tunnel.lastError != null) ...[
            const SizedBox(height: 8),
            Text(tunnel.lastError!,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.red)),
          ],
        ],
      ),
    );
  }
}

class _PortHealth extends StatelessWidget {
  final TunnelModel tunnel;
  final bool orphan;
  final String? processName;
  final int? pid;

  const _PortHealth({
    required this.tunnel,
    required this.orphan,
    this.processName,
    this.pid,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TunnelProvider>();
    if (orphan) {
      return Expanded(
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.amber.withValues(alpha: 0.5)),
              ),
              child: Text(
                '⚠️ 占用: ${processName ?? "未知进程"} (PID: $pid)',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.amber),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => provider.killOccupant(tunnel.id),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('一键强杀释放端口',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    }
    final listening = tunnel.status == TunnelStatus.running;
    final text = listening ? '本地端口监听正常' : '端口空闲';
    final color = listening ? AppColors.green : AppColors.textMuted;
    return Row(
      children: [
        Icon(listening ? Icons.check_circle : Icons.circle_outlined,
            size: 12, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _UrlBar extends StatelessWidget {
  final String url;

  const _UrlBar({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Text('公网地址:',
              style:
                  TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(url,
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w600,
                    color: AppColors.sky)),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制: $url',
                      style: const TextStyle(fontSize: 12)),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(Icons.copy, size: 13, color: AppColors.textSub),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              Process.run('cmd', ['/c', 'start', '', url]);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(Icons.open_in_new,
                  size: 13, color: AppColors.sky),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartStopButton extends StatelessWidget {
  final TunnelModel tunnel;

  const _StartStopButton({required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TunnelProvider>();
    final running = tunnel.status == TunnelStatus.running ||
        tunnel.status == TunnelStatus.starting ||
        tunnel.status == TunnelStatus.reconnecting;
    return InkWell(
      onTap: () => running
          ? provider.stopTunnel(tunnel.id)
          : provider.startTunnel(tunnel.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: running ? AppColors.green : AppColors.blue,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(running ? Icons.pause : Icons.play_arrow,
                size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(running ? '停止' : '启动',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E222B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: AppColors.textSub),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub)),
          ],
        ),
      ),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  final String provider;
  final String mode;

  const _ProviderBadge({required this.provider, required this.mode});

  @override
  Widget build(BuildContext context) {
    final isCf = provider == 'cloudflare';
    final label = isCf
        ? (mode == 'custom' ? 'Cloudflare 专属' : 'Cloudflare Quick')
        : 'ngrok';
    final color = isCf ? AppColors.amber : AppColors.indigo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TunnelStatus status;
  final int? pid;

  const _StatusBadge({required this.status, this.pid});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      TunnelStatus.running => (AppColors.green, '运行中${pid != null ? " (PID: $pid)" : ""}'),
      TunnelStatus.starting => (AppColors.blue, '启动中...'),
      TunnelStatus.reconnecting => (AppColors.amber, '重连中...'),
      TunnelStatus.error => (AppColors.red, '异常'),
      TunnelStatus.stopped => (AppColors.textMuted, '已停止'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color)),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  final Color color;

  const _TagChip(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

class _PortChip extends StatelessWidget {
  final String text;

  const _PortChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w600,
              color: AppColors.textMain)),
    );
  }
}
```

- [ ] **Step 2: 实现隧道管理页**

`lib/ui/tunnels_page.dart`（整体替换）：

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/tunnel_provider.dart';
import '../theme.dart';
import 'widgets/new_tunnel_dialog.dart';
import 'widgets/tunnel_card.dart';

class TunnelsPage extends StatelessWidget {
  const TunnelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('隧道管理',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  SizedBox(height: 2),
                  Text('管理本地端口与 Docker 容器上的内网穿透实例',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSub)),
                ],
              ),
              const Spacer(),
              InkWell(
                onTap: () => showDialog(
                    context: context,
                    builder: (_) => const NewTunnelDialog()),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add, size: 14, color: Colors.white),
                      SizedBox(width: 5),
                      Text('新建穿透条目',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.tunnels.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 60),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                children: [
                  Icon(Icons.hub_outlined,
                      size: 32, color: AppColors.textMuted),
                  SizedBox(height: 10),
                  Text('尚未配置任何隧道',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSub)),
                  SizedBox(height: 4),
                  Text('点击右上角「新建穿透条目」开始',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            )
          else
            ...provider.tunnels.map((t) => TunnelCard(tunnel: t)),
        ],
      ),
    );
  }
}
```

注意：本文件引用了 `new_tunnel_dialog.dart`（Task 13 创建）。为保持本任务可编译，先创建**最简占位** `lib/ui/widgets/new_tunnel_dialog.dart`：

```dart
import 'package:flutter/material.dart';

class NewTunnelDialog extends StatelessWidget {
  const NewTunnelDialog({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
```

Task 13 会整体替换该文件。

- [ ] **Step 3: 概览页回填隧道卡片**

修改 `lib/ui/dashboard_page.dart`：在 4 宫格 `Row` 之后追加：

```dart
          const SizedBox(height: 18),
          Row(
            children: [
              const Text('隧道列表',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub)),
              const Spacer(),
              Text('${provider.tunnels.length} 个已配置',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          if (provider.tunnels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('前往「隧道管理」新建第一条穿透',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ),
            )
          else
            ...provider.tunnels.map((t) => TunnelCard(tunnel: t)),
```

并在文件头补 import：

```dart
import 'widgets/tunnel_card.dart';
```

- [ ] **Step 4: 编译验证**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter analyze
flutter build windows --debug
```

- [ ] **Step 5: 运行冒烟（手动）**

启动 exe → 「隧道管理」页点击「新建穿透条目」（当前为 Loading 占位）→ 关闭弹窗。确认卡片组件在无数据时空态正常。

- [ ] **Step 6: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/ui/widgets/tunnel_card.dart easy_tunnel/app/lib/ui/widgets/new_tunnel_dialog.dart easy_tunnel/app/lib/ui/tunnels_page.dart easy_tunnel/app/lib/ui/dashboard_page.dart
git commit -m "feat(easy-tunnel): tunnel cards and tunnels management page

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

### Task 13: 新建穿透弹窗（Docker 智能带入 + 端口探测强杀）

**Files:**
- Modify: `easy_tunnel/app/lib/ui/widgets/new_tunnel_dialog.dart`（整体替换 Task 12 的占位实现）

**Interfaces:**
- Consumes: `TunnelProvider`（Task 9）、`DockerContainer`（Task 3）、`PortStatus`（Task 4）
- Produces: `class NewTunnelDialog extends StatefulWidget { const NewTunnelDialog({super.key}); }`
- 表单字段与行为：
  - 隧道名称（TextEditingController）
  - 目标端口（数字输入 + Docker 下拉：选中容器后自动填端口与名称）
  - 服务商单选：Cloudflare / ngrok（默认 Cloudflare）
  - 域名模式单选：自动随机（quick）/ 专属自定义（custom，显示域名输入框）
  - 【探测端口占用】按钮：调用 `provider.inspectPort(port)` 展示结果；若被占用显示进程名与 PID，并出现【一键强杀释放端口】按钮（调用 `PortMonitorService.killProcessTree` 走 `provider.portMonitor` —— 注意 Task 9 已把 `portMonitor` 暴露为 public final 字段，可直接调用）
  - 【保存并加入】：校验端口为 1..65535 的整数，构造 `TunnelModel(id: provider.newId(), ...)` 调 `provider.addTunnel`，`Navigator.pop`。
  - 保存后若端口已被非空进程占用，不阻断保存（用户可稍后处理）。

- [ ] **Step 1: 实现弹窗**

`lib/ui/widgets/new_tunnel_dialog.dart`（整体替换）：

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/tunnel_model.dart';
import '../../providers/tunnel_provider.dart';
import '../../services/port_monitor_service.dart';
import '../../theme.dart';

class NewTunnelDialog extends StatefulWidget {
  const NewTunnelDialog({super.key});

  @override
  State<NewTunnelDialog> createState() => _NewTunnelDialogState();
}

class _NewTunnelDialogState extends State<NewTunnelDialog> {
  final _nameCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '5173');
  final _domainCtrl = TextEditingController();

  String _provider = 'cloudflare';
  String _mode = 'quick';
  String? _dockerSelection;
  PortStatus? _probe;
  bool _probing = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _portCtrl.dispose();
    _domainCtrl.dispose();
    super.dispose();
  }

  Future<void> _probePort() async {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) return;
    setState(() => _probing = true);
    final provider = context.read<TunnelProvider>();
    final result = await provider.inspectPort(port);
    if (!mounted) return;
    setState(() {
      _probe = result;
      _probing = false;
    });
  }

  Future<void> _killProbed() async {
    final probe = _probe;
    if (probe?.pid == null) return;
    final provider = context.read<TunnelProvider>();
    await provider.portMonitor.killProcessTree(probe!.pid!);
    await _probePort();
  }

  void _applyDocker(String? label) {
    if (label == null) return;
    final provider = context.read<TunnelProvider>();
    for (final c in provider.dockerContainers) {
      if (c.label == label && c.hostPorts.isNotEmpty) {
        setState(() {
          _dockerSelection = c.name;
          _portCtrl.text = c.hostPorts.first.toString();
          if (_nameCtrl.text.isEmpty) _nameCtrl.text = c.name;
        });
        return;
      }
    }
  }

  Future<void> _save() async {
    final port = int.tryParse(_portCtrl.text.trim());
    if (_nameCtrl.text.trim().isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请填写名称与合法端口 (1-65535)',
            style: TextStyle(fontSize: 12)),
      ));
      return;
    }
    final provider = context.read<TunnelProvider>();
    final tunnel = TunnelModel(
      id: provider.newId(),
      name: _nameCtrl.text.trim(),
      targetPort: port,
      dockerContainerName: _dockerSelection,
      provider: _provider,
      mode: _mode,
      customDomain: _mode == 'custom' && _domainCtrl.text.trim().isNotEmpty
          ? _domainCtrl.text.trim()
          : null,
    );
    await provider.addTunnel(tunnel);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final dockerList = provider.dockerContainers
        .where((c) => c.hostPorts.isNotEmpty)
        .toList();

    return Dialog(
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('新建内网穿透条目',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 16, color: AppColors.textSub),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _FieldLabel('隧道名称'),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: _inputDecoration('例如: 财务分析前端服务'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const _FieldLabel('目标端口'),
                const Spacer(),
                InkWell(
                  onTap: _probing ? null : _probePort,
                  child: Text(
                    _probing ? '探测中...' : '探测端口占用',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.sky),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                    decoration: _inputDecoration('8080'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSub),
                    decoration: _inputDecoration('从运行中的 Docker 容器快捷选择'),
                    items: dockerList
                        .map((c) => DropdownMenuItem(
                              value: c.label,
                              child: Text(c.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSub)),
                            ))
                        .toList(),
                    onChanged: _applyDocker,
                  ),
                ),
              ],
            ),
            if (_probe != null) ...[
              const SizedBox(height: 8),
              _ProbeResult(
                probe: _probe!,
                onKill: _killProbed,
              ),
            ],
            const SizedBox(height: 14),
            const _FieldLabel('穿透服务商'),
            Row(
              children: [
                _ChoiceTile(
                  label: 'Cloudflare',
                  selected: _provider == 'cloudflare',
                  onTap: () => setState(() => _provider = 'cloudflare'),
                ),
                const SizedBox(width: 10),
                _ChoiceTile(
                  label: 'ngrok',
                  selected: _provider == 'ngrok',
                  onTap: () => setState(() => _provider = 'ngrok'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _FieldLabel('域名分配'),
            Row(
              children: [
                _ChoiceTile(
                  label: '自动随机分配 (免配置)',
                  selected: _mode == 'quick',
                  onTap: () => setState(() => _mode = 'quick'),
                  expand: true,
                ),
                const SizedBox(width: 10),
                _ChoiceTile(
                  label: '专属自定义域名',
                  selected: _mode == 'custom',
                  onTap: () => setState(() => _mode = 'custom'),
                  expand: true,
                ),
              ],
            ),
            if (_mode == 'custom') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _domainCtrl,
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    color: Colors.white),
                decoration: _inputDecoration('如 app.mydomain.com'),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSub)),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _save,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('保存并加入',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSub)),
      );
}

class _ChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blue.withValues(alpha: 0.12)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.border,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : AppColors.textSub)),
      ),
    );
    return expand ? Expanded(child: tile) : tile;
  }
}

class _ProbeResult extends StatelessWidget {
  final PortStatus probe;
  final VoidCallback onKill;

  const _ProbeResult({required this.probe, required this.onKill});

  @override
  Widget build(BuildContext context) {
    if (!probe.inUse) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppColors.green.withValues(alpha: 0.4)),
        ),
        child: Text('端口 ${probe.port} 空闲，可以立即穿透',
            style: const TextStyle(fontSize: 11, color: AppColors.green)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '端口 ${probe.port} 被 ${probe.processName ?? "未知进程"} (PID: ${probe.pid}) 占用',
              style:
                  const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
          ),
          InkWell(
            onTap: onKill,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('一键强杀释放端口',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 编译验证**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter analyze
flutter build windows --debug
```

- [ ] **Step 3: 运行冒烟（手动）**

启动 exe → 新建穿透：确认 Docker 下拉能列出本机容器（若 Docker 运行中）、端口探测能显示占用进程并可强杀、保存后卡片出现在列表。

- [ ] **Step 4: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/ui/widgets/new_tunnel_dialog.dart
git commit -m "feat(easy-tunnel): new tunnel dialog with docker picker and port probe

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 14: 底部日志抽屉

**Files:**
- Modify: `easy_tunnel/app/lib/ui/widgets/log_drawer.dart`（整体替换占位实现）

**Interfaces:**
- Consumes: `TunnelProvider.selectedLogTunnelId`、`TunnelModel.logs`（Task 9）
- Produces: `class LogDrawer extends StatefulWidget { const LogDrawer({super.key}); }`
- 行为：
  - 未选择隧道时显示提示「点击隧道卡片上的“实时日志”查看输出」。
  - 选择后标题显示 `名称 (端口)`，列出 `logs`，新日志自动滚动到底部。
  - 【清空】清空该隧道日志；右侧箭头折叠/展开（折叠高度 28，展开 160）。
  - 纯黑终端风格（`#090B0E`），使用 `Consolas` 字体。

- [ ] **Step 1: 实现日志抽屉**

`lib/ui/widgets/log_drawer.dart`（整体替换）：

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/tunnel_provider.dart';
import '../../theme.dart';

class LogDrawer extends StatefulWidget {
  const LogDrawer({super.key});

  @override
  State<LogDrawer> createState() => _LogDrawerState();
}

class _LogDrawerState extends State<LogDrawer> {
  final _scrollCtrl = ScrollController();
  bool _collapsed = false;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final id = provider.selectedLogTunnelId;
    final tunnel = id == null ? null : provider.tunnelById(id);
    _scrollToBottom();

    return Container(
      height: _collapsed ? 28 : 160,
      decoration: const BoxDecoration(
        color: Color(0xFF090B0E),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF101216),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal,
                    size: 12, color: AppColors.green),
                const SizedBox(width: 8),
                const Text('控制台实时输出:',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSub)),
                const SizedBox(width: 8),
                if (tunnel != null)
                  Text('${tunnel.name} (${tunnel.targetPort})',
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w600,
                          color: AppColors.sky)),
                const Spacer(),
                if (tunnel != null)
                  InkWell(
                    onTap: () => provider.clearLogs(tunnel.id),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text('清空',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSub)),
                    ),
                  ),
                InkWell(
                  onTap: () => setState(() => _collapsed = !_collapsed),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Icon(
                      _collapsed
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 14,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_collapsed)
            Expanded(
              child: tunnel == null
                  ? const Center(
                      child: Text('点击隧道卡片上的「实时日志」查看输出',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted)),
                    )
                  : tunnel.logs.isEmpty
                      ? const Center(
                          child: Text('暂无日志输出',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted)),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          itemCount: tunnel.logs.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              tunnel.logs[i],
                              style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.5,
                                  fontFamily: 'Consolas',
                                  color: AppColors.textSub),
                            ),
                          ),
                        ),
            ),
        ],
      ),
    );
  }
}
```

注意：`notifyListeners` 在 Flutter 中标注为 `@protected`，UI 层不得直接调用；清空日志统一走 Task 9 提供的 `provider.clearLogs(id)`。

- [ ] **Step 2: 编译验证**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter analyze
flutter build windows --debug
```

- [ ] **Step 3: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/ui/widgets/log_drawer.dart
git commit -m "feat(easy-tunnel): bottom log drawer with auto scroll

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 15: 系统设置页

**Files:**
- Modify: `easy_tunnel/app/lib/ui/settings_page.dart`（整体替换占位实现）

**Interfaces:**
- Consumes: `TunnelProvider`（Task 9）、`AppSettings`（Task 8）
- Produces: `class SettingsPage extends StatefulWidget { const SettingsPage({super.key}); }`
- 页面卡片（对齐设计稿图 2）：
  1. **穿透观测与日志**：`详细日志模式` Switch → `settings.detailedLogs`，改动即 `saveSettings()`。
  2. **端口与进程冲突管理**：展示 Metrics 端口说明文案（静态说明「每 6 秒自动巡检」）、冲突自动策略说明。
  3. **穿透服务凭证**：Cloudflare Tunnel Token 与 ngrok Authtoken 输入框（`obscureText: true`，聚焦外可点「显示」切换），失焦或点保存时写回 `settings` 并 `saveSettings()`。展示时脱敏：已有值只显示前 4 后 4 位（`_mask()`）。
  4. **依赖状态**：显示 cloudflared / ngrok 是否就绪，【重新检测】按钮调用 `provider.recheckDependencies()`（Task 9 提供的公开方法）。
  5. **系统与托盘偏好**：`关闭窗口时最小化到托盘` Switch → `settings.closeToTray`；`开机自动启动` Switch → 写注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，值名 `EasyTunnel`，数据 `Platform.resolvedExecutable`。
  6. 底部版本信息：`Easy Tunnel 助手 v1.0.1 · Flutter Windows Desktop`。

- [ ] **Step 1: 实现设置页**

`lib/ui/settings_page.dart`（整体替换）：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/tunnel_provider.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _cfCtrl;
  late final TextEditingController _ngCtrl;
  bool _obscureCf = true;
  bool _obscureNg = true;

  @override
  void initState() {
    super.initState();
    final settings = context.read<TunnelProvider>().settings;
    _cfCtrl = TextEditingController(text: settings.cloudflareToken);
    _ngCtrl = TextEditingController(text: settings.ngrokToken);
  }

  @override
  void dispose() {
    _cfCtrl.dispose();
    _ngCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveTokens() async {
    final provider = context.read<TunnelProvider>();
    provider.settings.cloudflareToken = _cfCtrl.text.trim();
    provider.settings.ngrokToken = _ngCtrl.text.trim();
    await provider.saveSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('凭证已保存', style: TextStyle(fontSize: 12)),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _recheckDeps() async {
    final provider = context.read<TunnelProvider>();
    await provider.recheckDependencies();
  }

  Future<void> _setStartup(bool enabled) async {
    final provider = context.read<TunnelProvider>();
    try {
      if (enabled) {
        await Process.run('reg', [
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'EasyTunnel',
          '/t',
          'REG_SZ',
          '/d',
          Platform.resolvedExecutable,
          '/f',
        ]);
      } else {
        await Process.run('reg', [
          'delete',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'EasyTunnel',
          '/f',
        ]);
      }
    } catch (_) {}
    provider.settings.launchAtStartup = enabled;
    await provider.saveSettings();
  }

  String _mask(String token) {
    if (token.length <= 8) return token.isEmpty ? '未配置' : '****';
    return '${token.substring(0, 4)}****${token.substring(token.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final settings = provider.settings;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('设置',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 16),
          _SettingCard(
            title: '穿透观测与日志',
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('详细模式',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      SizedBox(height: 3),
                      Text('额外保留完整子进程输出；关闭后仅记录启动、错误与公网 URL 关键行。',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSub)),
                    ],
                  ),
                ),
                Switch(
                  value: settings.detailedLogs,
                  activeTrackColor: AppColors.blue,
                  onChanged: (v) async {
                    settings.detailedLogs = v;
                    await provider.saveSettings();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            title: '端口与进程冲突管理',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('巡检频率',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSub)),
                    const SizedBox(width: 24),
                    const Text('每 6 秒自动探测所有隧道端口',
                        style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Consolas',
                            color: Colors.white)),
                    const Spacer(),
                    Text('当前冲突 ${provider.conflictCount} 处',
                        style: TextStyle(
                            fontSize: 11,
                            color: provider.conflictCount > 0
                                ? AppColors.amber
                                : AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                    '端口被占用时会识别具体占用进程（如 node.exe、python.exe），可在隧道卡片上执行一键强杀 taskkill /F /T。',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            title: '穿透服务凭证',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cloudflare Tunnel Token',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSub)),
                const SizedBox(height: 6),
                _TokenField(
                  controller: _cfCtrl,
                  obscure: _obscureCf,
                  hint: '粘贴 cloudflared tunnel token',
                  onToggle: () =>
                      setState(() => _obscureCf = !_obscureCf),
                ),
                const SizedBox(height: 4),
                Text('当前: ${_mask(settings.cloudflareToken)}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                const Text('ngrok Authtoken',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSub)),
                const SizedBox(height: 6),
                _TokenField(
                  controller: _ngCtrl,
                  obscure: _obscureNg,
                  hint: '粘贴 ngrok authtoken',
                  onToggle: () =>
                      setState(() => _obscureNg = !_obscureNg),
                ),
                const SizedBox(height: 4),
                Text('当前: ${_mask(settings.ngrokToken)}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted)),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: _saveTokens,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('保存凭证',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            title: '本地穿透二进制',
            child: Row(
              children: [
                _DepBadge(
                    name: 'cloudflared', ready: provider.cloudflaredReady),
                const SizedBox(width: 14),
                _DepBadge(name: 'ngrok', ready: provider.ngrokReady),
                const Spacer(),
                InkWell(
                  onTap: _recheckDeps,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text('重新检测 / 下载',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSub)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            title: '系统与托盘偏好',
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('关闭窗口时最小化到托盘',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          SizedBox(height: 3),
                          Text('关闭后隧道保持在线，托盘中可再次打开或彻底退出。',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSub)),
                        ],
                      ),
                    ),
                    Switch(
                      value: settings.closeToTray,
                      activeTrackColor: AppColors.blue,
                      onChanged: (v) async {
                        settings.closeToTray = v;
                        await provider.saveSettings();
                      },
                    ),
                  ],
                ),
                const Divider(
                    color: AppColors.border, height: 20, thickness: 1),
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('开机自动启动',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          SizedBox(height: 3),
                          Text('写入 HKCU Run 注册表项，登录后自动拉起应用。',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSub)),
                        ],
                      ),
                    ),
                    Switch(
                      value: settings.launchAtStartup,
                      activeTrackColor: AppColors.blue,
                      onChanged: _setStartup,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text('Easy Tunnel 助手 v1.0.1 · Flutter Windows Desktop',
                style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Consolas',
                    color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSub)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TokenField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final String hint;
  final VoidCallback onToggle;

  const _TokenField({
    required this.controller,
    required this.obscure,
    required this.hint,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(
          fontSize: 12, fontFamily: 'Consolas', color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontSize: 11, color: AppColors.textMuted),
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        suffixIcon: IconButton(
          icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              size: 14,
              color: AppColors.textMuted),
          onPressed: onToggle,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

class _DepBadge extends StatelessWidget {
  final String name;
  final bool ready;

  const _DepBadge({required this.name, required this.ready});

  @override
  Widget build(BuildContext context) {
    final color = ready ? AppColors.green : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('$name ${ready ? "已就绪" : "未就绪"}',
              style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 编译验证**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter analyze
flutter build windows --debug
```

- [ ] **Step 3: Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/app/lib/ui/settings_page.dart
git commit -m "feat(easy-tunnel): settings page with tokens and system preferences

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

### Task 16: 集成验证与 Release 构建

**Files:**
- Modify: `easy_tunnel/README.md`（补充构建与使用说明）

**Interfaces:**
- Consumes: 全部前序任务。
- Produces: 可发布的 `build\windows\x64\runner\Release\easy_tunnel.exe`。

- [ ] **Step 1: 全量静态检查与单元测试**

```bash
cd /d/projects/ops-center/easy_tunnel/app
flutter analyze
flutter test
```

Expected: analyze 零告警；所有测试 PASS（tunnel_model 3 + parsers 15 + port_monitor 3 + docker 3 + tunnel_engine 3 + storage 3 + provider 3，共 33 个）。

- [ ] **Step 2: Release 构建**

```bash
flutter build windows --release
```

Expected: 生成 `build\windows\x64\runner\Release\easy_tunnel.exe`。

- [ ] **Step 3: 端到端手动验收清单**

启动 Release 版 exe，逐项验证并记录结果：

1. **依赖自动下载**：首次启动，侧边栏 Cloudflare / ngrok 徽标在几十秒内由「未就绪」变「已就绪」；`%APPDATA%` 对应目录下 `bin\cloudflared.exe`、`bin\ngrok.exe` 存在。
2. **Docker 联动**：本机 Docker 运行中时，新建弹窗下拉框列出容器（如 `ops-center-api:8787`），选中后端口自动填入。
3. **免 Docker 手动端口**：PowerShell 运行 `python -m http.server 3000`；新建隧道填入端口 3000，启动 Cloudflare Quick，几十秒内卡片出现 `https://*.trycloudflare.com`，浏览器打开可见目录列表。
4. **端口冲突强杀**：关闭上一步的 Python 服务但保留僵尸监听（或另起 `node` 占住 3000）→ 隧道停止状态下卡片显示琥珀告警与进程名/PID → 点击【一键强杀释放端口】→ 告警消失。
5. **多隧道并发**：再新建一条 ngrok 隧道指向另一端口并启动，两条 URL 同时在卡片上显示且互不影响。
6. **日志抽屉**：点击任一卡片【实时日志】，底部抽屉滚动输出子进程日志；折叠/展开/清空按钮生效。
7. **托盘生命周期**：点右上角关闭 → 窗口隐藏、托盘图标在；托盘右键「停止全部隧道」生效；托盘「打开主界面」恢复窗口；「彻底退出」后任务管理器无 `cloudflared.exe` / `ngrok.exe` 残留。
8. **凭证持久化**：设置页填入 Cloudflare Token → 重启应用后输入框回填且显隐切换正常（脱敏展示）。

- [ ] **Step 4: 更新 README 构建说明**

在 `easy_tunnel/README.md` 末尾追加：

```markdown
---

## Windows 桌面应用（Flutter）

源码目录：`easy_tunnel/app`

```powershell
cd easy_tunnel\app
flutter pub get
flutter analyze
flutter test
flutter build windows --release
# 产物: build\windows\x64\runner\Release\easy_tunnel.exe
```

首次启动会自动下载 `cloudflared` 与 `ngrok` 到应用数据目录的 `bin\` 下。
```

- [ ] **Step 5: 最终 Commit**

```bash
cd /d/projects/ops-center
git add easy_tunnel/README.md easy_tunnel/docs/implementation-plan.md
git status --short easy_tunnel
git commit -m "docs(easy-tunnel): build instructions and implementation plan

Co-Authored-By: BaoCode <noreply@baocode.dev>"
```

---

## 自检记录（Spec 覆盖映射）

| Spec 要求 | 对应任务 |
| :--- | :--- |
| Flutter 纯原生进程托管架构 | Task 1、6、9 |
| Docker 容器扫描（可失败降级） | Task 3、5、13 |
| 手动端口（免 Docker） | Task 13（端口输入框独立于 Docker 下拉） |
| 端口监控与一键强杀 netstat/tasklist/taskkill | Task 3、4、9、12 |
| Cloudflare Quick 域名正则捕获 | Task 3、6、9 |
| Cloudflare 自定义 Token 隧道 | Task 6、8、9、15 |
| ngrok 随机/自定义域名 | Task 6、9 |
| 多隧道并发管理 | Task 9、12 |
| 依赖二进制自动下载 | Task 7、15、16 |
| 认证错误识别与通知 | Task 3、9、10（local_notifier） |
| 孤儿进程防御（应用退出级联清理） | Task 6（taskkill /T）、Task 10（托盘退出 stopAll） |
| 配置持久化 %APPDATA% config.json | Task 8 |
| UI 对标设计稿（暗黑主题/侧边栏/统计卡/图表/日志抽屉） | Task 10、11、12、14、15 |
| 托盘常驻与关闭行为 | Task 10 |
| 开机自启（HKCU Run） | Task 15 |
| Token 脱敏 | Task 15（`_mask`）、Task 9（日志不打印 token） |
| 日志环形缓冲 200 行 | Task 9 |
| 重连退避（2s/4s/8s，最多 3 次） | Task 9 |

已知取舍：
- 概览页堆叠柱状图为装饰性静态数据（本应用不代理流量，无真实请求统计）；四张统计卡全部由真实 provider 状态驱动。
- 提供商级别的流量/请求计数不在本期范围（需代理层，YAGNI）。



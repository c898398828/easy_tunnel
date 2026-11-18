# Easy Tunnel (内网穿透管家) 架构设计规范

**文档状态**: Approved (已对齐)  
**设计日期**: 2026-11-13  
**目标平台**: Windows 11 / Windows 10 (x86_64)  
**技术选型**: Flutter Desktop (Dart 原生进程管理 + Material 3 暗黑主题)  
**参考原型**: `easy_tunnel/prototype.html` (对标 Cursor 助手 v1.0.1 视觉规范)

---

## 1. 概述与背景

### 1.1 问题背景
在本地 Windows 开发机上调试 Web 应用、小程序、第三方 Webhook 回调或远程服务时，通常需要将本地运行的端口（无论是直接在宿主机运行还是运行在 Docker 容器中）映射暴露至公网。
原有的 Linux 脚本方案（`start-tunnel.sh`）依赖 Linux 网络命名空间（`ip netns`）与 Bash 命令行，不适用于 Windows 开发者的日常可视化操作。

### 1.2 核心目标
构建一款原生 Windows 桌面端小工具 **Easy Tunnel**：
1. **开箱即用**：无需手动安装复杂环境，一键托管并拉起 Cloudflare Tunnel 与 ngrok。
2. **极简操作**：支持从运行中的 Docker 容器中一键带入映射端口，同时也支持无 Docker 环境的手动任意端口输入。
3. **域名灵活**：既支持免注册的随机临时公网域名（`*.trycloudflare.com`），又支持绑定私有专属域名。
4. **多隧道并发**：支持多服务同时在线与独立控制（如前端 `8080` 与后端 `3000` 并行）。
5. **冲突一键释放**：自动探测目标端口是否被本地进程（如残留的 `node.exe`）占用，界面展示占用者与 PID，并支持一键 `taskkill` 强杀释放。
6. **精致视觉体验**：严格对标 **Cursor 助手 v1.0.1** 暗黑极简桌面风格，支持系统托盘后台常驻。

---

## 2. 总体架构设计

采用 **Flutter 纯原生进程托管架构（方案一）**，避免引入额外的常驻后台守护服务，保证单应用分发、轻量低功耗与无残留进程退出。

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI 表现层                     │
│  [主界面/隧道概览大屏] [多隧道卡片管理] [系统设置] [日志抽屉] │
└───────────────────────────┬────────────────────────────┘
                            │ Provider / Riverpod 状态流
┌───────────────────────────▼────────────────────────────┐
│                    业务服务层 (Services)                 │
│   DockerService (容器扫描)    TunnelManager (生命周期调度) │
│   PortMonitorService (端口强杀) StorageService (持久化) │
│   DependencyService (依赖管理)                          │
└───────────────────────────┬────────────────────────────┘
                            │ dart:io Process
┌───────────────────────────▼────────────────────────────┐
│                 进程管控与解析引擎 (Engine)               │
│   - cloudflared.exe (免配 Quick 模式 / 自定义 Token 模式)│
│   - ngrok.exe (随机域名模式 / 自定义域名模式)             │
│   - docker.exe (端口与容器探测)                          │
│   - netstat / taskkill (端口占用检测与一键释放)           │
└───────────────────────────┬────────────────────────────┘
                            │ 异步流 (Stream)
┌───────────────────────────▼────────────────────────────┐
│               系统集成层 (Windows Desktop)              │
│    tray_manager (系统托盘)   window_manager (窗口行为控制) │
└────────────────────────────────────────────────────────┘
```

---

## 3. 核心功能与模块设计

### 3.1 Docker 容器智能探测 (`DockerService`)
- **执行命令**：`docker ps --format "{{.ID}}|{{.Names}}|{{.Ports}}|{{.Status}}"`
- **解析逻辑**：正则表达式匹配宿主机映射端口（如 `0.0.0.0:8080->80/tcp` $\rightarrow$ 提取 `8080`）。
- **交互联动**：在新建/编辑穿透条目时，下拉列表自动展示当前在线的容器（如 `ops-center-web:8080`），点击后自动带入端口与容器名。
- **解耦特性**：Docker 探测为完全可选功能。若未启动 Docker 或针对纯本地服务（Vite / Spring Boot 等），用户可直接手动输入端口。

### 3.2 端口监控与一键强杀 (`PortMonitorService`)
- **冲突检测**：
  - 检查命令：调用 Windows 原生 `netstat -ano -p tcp` 查询目标端口占用的 PID。
  - 进程解析：调用 `tasklist /FI "PID eq <PID>"` 解析出对应的可执行程序名称（如 `node.exe`、`com.docker.backend.exe`）。
- **界面报警**：若端口被非目标进程占用，卡片呈现黄色预警徽标：`⚠️ 端口占用: node.exe (PID: 9412)`。
- **一键强杀**：提供【一键强杀释放端口】按钮，触发执行 `taskkill /F /T /PID <PID>`，秒级释放端口，无需手动打开任务管理器。

### 3.3 穿透执行引擎 (`TunnelProcessEngine`)
- **Cloudflare 快速免配模式**：
  - 启动命令：`cloudflared.exe tunnel --url http://127.0.0.1:<PORT>`
  - 域名正则捕获：监听 `stderr` 流，匹配 `https://[a-zA-Z0-9-]+\.trycloudflare\.com`。
- **Cloudflare 自定义模式**：
  - 启动命令：`cloudflared.exe tunnel run --token <TOKEN>`
  - 域名绑定：直接读取用户配置的自定义二级域名（如 `app.mycompany.com`）。
- **ngrok 模式**：
  - 启动命令：`ngrok.exe http 127.0.0.1:<PORT> --log stdout`（如有配置自定义域名则追加 `--domain=<CUSTOM_DOMAIN>`）。
  - 域名正则捕获：监听 `stdout` 流，匹配 `https://[a-zA-Z0-9.-]+\.ngrok-free\.app` 或自定义域名。
- **孤儿进程防御**：
  - 退出软件或停止单个服务时，执行 `taskkill /F /T /PID <PID>` 连带树形子进程彻底销毁，确保无后台幽灵进程。

### 3.4 依赖二进制自动管理 (`DependencyService`)
- **目录规划**：默认存放于 `%LOCALAPPDATA%\EasyTunnel\bin\`。
- **自动检查与静默拉取**：
  - 首次运行检查 `cloudflared.exe` 与 `ngrok.exe`。
  - 缺失时弹出轻量下载进度，拉取官方最新 Windows amd64 二进制文件。

---

## 4. UI 视觉设计规范 (对标 Cursor 助手 v1.0.1)

全套 UI 采用统一的现代化暗黑微光设计语言，分为以下视图：

### 4.1 侧边栏与标题栏
- **顶栏融合**：Windows 原生无边框标题栏与侧边栏无缝连接，左上角显示 `Easy Tunnel 助手 v1.0.1`，右上角集成极简窗口控制按钮。
- **导航分组**：
  - 数据概览（激活态深灰高亮背景 + 蓝色折线图标）；
  - 隧道管理（黄色柱状图图标）；
  - 穿透引擎（Cloudflare 带有绿色描边药丸徽标 `已接管`，ngrok 带有 `已就绪` 徽标）；
  - 设置（新建条目、系统设置、使用教程）；
  - 侧边栏底部常驻 Docker 状态指示与绿色呼吸灯。

### 4.2 数据概览大屏 (复刻图 1)
- **顶部时间范围分段控制胶囊**：近1小时 / 近1自然日 / 近10分钟 / 近一周 / 近一个月 (激活态) / 自定义 / 刷新。
- **堆叠柱状图卡片**：
  - 24小时/30天双层堆叠柱状图（深灰基底 + 绿色出站缓存段 + 蓝色直连段）；
  - 黄色平均虚线与左侧“平均”标签；
  - 交互式半透明高峰悬浮浮窗（展示当日总请求、直连调用、缓存命中与下行流量）。
- **4 宫格指标卡片**：
  - `穿透缓存命中率`：半圆环状进度仪表盘，大字呈现 `89.95%`；
  - `穿透连接数`：大字呈现 `991`，附带 `成功 921 / 异常 70`；
  - `吞吐数据量`：大字呈现 `211MB`，附带 `响应下行 210MB`；
  - `端口健康与诊断`：直观展示 `1 处冲突`，附带一键释放入口。
- **底部全年度在线方块矩阵**：
  - 7 行 x 52 列 GitHub 风格方形在线热力网格与月份时间刻度。

### 4.3 模块化卡片式设置页 (复刻图 2)
- **调用观测**：包含右侧蓝底【详细模式】复选框与描述说明。
- **端口设置**：右上角【编辑】链接，展示代理端口 `51345`、服务端口 `50700`，下附自动冲突策略说明。
- **穿透服务凭证**：展示脱敏后的 Tunnel Token 与默认域名后缀。
- **系统与托盘偏好**：开机自动拉起后台穿透与托盘后台常驻。

### 4.4 底部控制台日志抽屉
- 全黑控制台日志流，展示子进程实时 stdout/stderr，支持一键清空与最小化折叠。

---

## 5. 数据结构设计 (`TunnelModel`)

```dart
class TunnelModel {
  final String id;                    // UUID
  String name;                         // 显示名称
  int targetPort;                      // 本地监听端口
  String? dockerContainerName;         // 关联的 Docker 容器名 (可选)
  String provider;                     // 'cloudflare' | 'ngrok'
  String mode;                         // 'quick' | 'custom'
  String? customDomain;                // 自定义域名
  String? token;                       // 专用 Token (可选)
  TunnelStatus status;                 // stopped | starting | running | error
  String? publicUrl;                   // 捕获到的实际公网 URL
  int? processPid;                     // 正在运行的系统子进程 PID
  List<String> logs;                   // 内存保留的最近 200 行日志环形缓冲区

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
    List<String>? logs,
  }) : logs = logs ?? [];
}

enum TunnelStatus {
  stopped,
  starting,
  running,
  reconnecting,
  error,
}
```

---

## 6. 测试与验证策略

1. **Docker 联动验证**：
   - 在宿主机启动测试容器 `docker run -d -p 8080:80 nginx:alpine`；
   - 验证新建弹窗是否能秒级扫描并带入 `8080` 端口。
2. **纯手动非 Docker 端口验证**：
   - 在 Windows 本地命令行运行 `python -m http.server 3000`；
   - 手动填入端口 `3000`，启动 Cloudflare Quick 隧道，验证 `*.trycloudflare.com` 是否能成功打开 Python 目录。
3. **冲突进程强杀验证**：
   - 启动模拟占用端口的进程，观察卡片是否出现预警与进程名 PID；
   - 点击【一键强杀释放端口】，验证 `taskkill` 是否成功终止进程，卡片状态是否恢复空闲。
4. **多隧道并发稳定性验证**：
   - 同时启动 Cloudflare 隧道和 ngrok 隧道，验证两个公网 URL 是否互不干扰。
5. **系统托盘生命周期验证**：
   - 点击右上角关闭按钮，验证窗口是否最小化至托盘且穿透网络不断流；
   - 右键托盘选择【彻底退出】，验证子进程是否被完全回收清理。

# Easy Tunnel 对话记录与方案演进详录

本文档完整记录了围绕“内网穿透管理与 Windows 桌面可视化工具（Easy Tunnel）”的全部讨论内容、需求分析、技术选型和架构设计。

---

## 一、原始脚本解析与核心原理

### 1. 脚本定位
用户提供的 `start-tunnel.sh` 是一个基于 Linux Bash 编写的内网穿透运维管理脚本，集成了两大主流穿透工具：
- **Cloudflare Tunnel (`cloudflared`)**：支持出站隧道代理。
- **ngrok**：支持 HTTP/TCP 穿透代理。

### 2. 核心机制
- **网络命名空间隔离 (`netns`)**：
  脚本配置了 `NETNS="proxytest"`，通过 `sudo ip netns exec proxytest` 将穿透进程与本地服务隔离在独立的 Linux 网络命名空间中运行，并主动清除了 `HTTP_PROXY` / `ALL_PROXY` 环境变量，防止本地代理污染穿透流量。
- **生命周期管理**：
  提供交互式菜单和命令行参数，支持 `install`、`start`（前台/后台）、`status`、`stop`、`config`、`show`。
- **测试验证链路**：
  ```bash
  sudo ip netns exec proxytest python3 -m http.server 8888 --bind 127.0.0.1
  ```
  该命令在 `proxytest` 命名空间内部启动一个测试 HTTP 服务，验证外部公网流量是否能成功路由进该命名空间。

---

## 二、使用前置准备与避坑指南

若在 Linux 环境下运行该脚本，需要准备：
1. **系统环境**：
   - Linux x86_64 机器；
   - `sudo` 提权；
   - 依赖命令：`wget`、`tar`、`iproute2`。
2. **账号与 Token**：
   - **ngrok**：官网注册获取 Authtoken。
   - **Cloudflare**：需托管域名的 Cloudflare 账号，在 Zero Trust 后台创建 Tunnel 获取长串 Token。
3. **网络命名空间避坑点**：
   - 若使用默认 `proxytest`，必须先创建 namespace 并拉起 `lo` 回环网卡：
     ```bash
     sudo ip netns add proxytest
     sudo ip netns exec proxytest ip link set lo up
     ```
   - 若不需要隔离，可在配置中将 `NETNS` 置空。

---

## 三、可视化形态探讨与技术选型

针对“能否做成可视化小软件”，探讨了三种形态：
1. **轻量 Web 控制台**：适合无显示器的远程 Linux 服务器，通过浏览器访问管理面板。
2. **终端交互式面板 (TUI)**：类似 lazygit / htop，直接在 SSH 终端按键操作。
3. **原生桌面客户端 (Flutter / Electron / Tauri)**：适合有图形界面的开发机。

### Flutter 桌面端优劣势分析：
- **优势**：
  - Material 3 现代质感，动画流畅，颜值极高；
  - 采用 AOT 编译为原生机器码，内存占用（30~60MB）和冷启动显著优于 Electron；
  - 优秀的系统托盘集成（`tray_manager`），支持常驻任务栏后台；
  - 一套代码可跨 Windows、macOS、Linux、手机端。
- **局限与场景匹配**：
  - 在纯 SSH 无桌面云服务器上无法运行（缺少 X11/Wayland 图形环境）；
  - 但**在 Windows 开发机本地使用时，Flutter 是极佳选择**。

---

## 四、Windows 开发机场景定制需求对齐

用户明确使用场景：**在 Windows 开发机上使用，主要针对 Docker 容器端口做一键穿透与域名分配**。

经过多轮沟通，逐步对齐出以下核心需求：

| 决策维度 | 用户选择 | 方案说明 |
| :--- | :--- | :--- |
| **客户端形态** | **选项 A：Flutter 桌面端应用 (.exe)** | 原生 Windows 桌面程序，Material 3 界面，支持系统托盘常驻。 |
| **穿透与域名模式** | **选项 1：双模式支持** | 1. **快速免配模式**：自动随机公网域名（Cloudflare Quick / ngrok 免费临时）。<br>2. **自定义域名模式**：用户填入 Token，绑定专属二级域名。 |
| **目标端口交互** | **选项 A：Docker 智能识别 + 手动输入** | 自动扫描正在运行的 Docker 容器和映射端口供快捷下拉选用；同时保留手动输入框。 |
| **并发管理模式** | **选项 B：多隧道列表管理** | 支持同时建立多个穿透条目（如前端 8080 与后端 3000 并发在线），各自独立启停。 |
| **特别新增功能** | **主机进程监控与一键强杀** | 实时检测目标端口是否被本地进程占用（如残留的 `node.exe`），卡片上显示进程名与 PID，并提供红色按钮一键 `taskkill` 释放端口。 |
| **是否依赖 Docker** | **完全解耦（Docker 纯可选）** | 穿透底层直接转发到 `127.0.0.1:<端口>`。未启动 Docker 时，直接手动输入任意本地服务端口（Vite/Spring Boot/Python）均可正常穿透。 |

---

## 五、系统架构设计（纯 Dart 原生进程托管）

确认采用 **方案一：Flutter 纯原生进程托管架构**：

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI 表现层                     │
│  [主界面/隧道卡片列表] [添加/编辑弹窗] [实时日志抽屉] [设置页] │
└───────────────────────────┬────────────────────────────┘
                            │ Provider / Riverpod 状态流
┌───────────────────────────▼────────────────────────────┐
│                    业务服务层 (Services)                 │
│   DockerService (容器扫描)    TunnelManager (生命周期调度) │
│   PortMonitorService (端口强杀) StorageService (持久化) │
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

### 关键业务流程：
1. **Docker 扫描**：
   执行 `docker ps --format "{{.ID}}|{{.Names}}|{{.Ports}}|{{.Status}}"`，正则提取 `0.0.0.0:8080->80/tcp` 中的宿主机端口。
2. **端口冲突探测与强杀**：
   - 探测：`netstat -ano -p tcp | findstr :<port>` 获取 PID，再通过 `tasklist /FI "PID eq <PID>"` 获得进程名。
   - 强杀：调用 `taskkill /F /T /PID <PID>`，秒级释放端口。
3. **公网域名动态捕获**：
   - 监听子进程 stdout/stderr 流。
   - Cloudflare Quick 匹配：`https://[a-zA-Z0-9-]+\.trycloudflare\.com`。
   - ngrok 匹配：`https://[a-zA-Z0-9.-]+\.ngrok-free\.app`。
4. **后台常驻与安全清理**：
   - 窗口最小化/关闭时收纳至右下角系统托盘；
   - 托盘右键彻底退出时，级联杀掉所有运行中的穿透子进程，绝不残留“幽灵进程”。

---

## 六、交互式原型交付

已制作完整的高保真交互式原型并交付：
- 原型文件位置：`easy_tunnel/prototype.html`
- 包含特性：
  - Windows 11 视觉规范与托盘模拟；
  - 运行中的 Cloudflare 临时域名卡片与一键复制；
  - 端口冲突与 `node.exe` 一键强杀交互演示；
  - 带有 Docker 容器自动识别下拉框的新建穿透弹窗；
  - 底部黑色终端风格的实时控制台日志抽屉。

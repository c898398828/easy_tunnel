# Easy Tunnel 贡献指南 (Contributing Guide)

感谢你关注并愿意为 **Easy Tunnel** 贡献代码或文档！开源社区的繁荣离不开每一位贡献者的参与。在开始之前，请花几分钟阅读以下贡献规范。

---

## 目录

- [行为准则](#行为准则)
- [如何贡献](#如何贡献)
  - [报告问题 (Bug Report)](#报告问题-bug-report)
  - [提出新特性建议 (Feature Request)](#提出新特性建议-feature-request)
  - [提交代码 (Pull Request)](#提交代码-pull-request)
- [本地开发环境搭建](#本地开发环境搭建)
  - [前置依赖](#前置依赖)
  - [获取源码与启动](#获取源码与启动)
  - [执行测试与静态分析](#执行测试与静态分析)
  - [构建 Windows 安装包](#构建-windows-安装包)
- [代码规范与风格](#代码规范与风格)
- [Git 提交信息规范 (Conventional Commits)](#git-提交信息规范-conventional-commits)

---

## 行为准则

本项目遵循 [Contributor Covenant](CODE_OF_CONDUCT.md) 行为准则。无论是提交 Issue 还是 PR，都请保持友好、包容和互相尊重的交流环境。

---

## 如何贡献

### 报告问题 (Bug Report)
如果你在使用 Easy Tunnel 过程中遇到了 Bug，请在提交 Issue 前：
1. 检查已有的 [Issues](https://github.com/c898398828/easy_tunnel/issues) 确认该问题尚未被汇报；
2. 尽可能提供详细的复现步骤、Windows 系统版本、Docker Desktop 版本以及控制台实时日志输出；
3. 使用我们的标准 Bug Issue 模版提交。

### 提出新特性建议 (Feature Request)
我们非常欢迎对界面交互、穿透协议适配、监控图表等提出有价值的建议。请在 Feature Request 模版中说明：
- 该特性的应用场景和解决的具体痛点；
- 预期的用户体验或界面交互原型。

### 提交代码 (Pull Request)
1. Fork 本项目到你的个人 GitHub 仓库；
2. 基于 `main` 分支拉取新的特性或修复分支（例如 `feature/custom-proxy-port` 或 `fix/log-drawer-scroll`）；
3. 进行代码编写，确保遵循项目的架构与代码规范；
4. 运行 `flutter test --no-pub` 和 `flutter analyze` 确保所有单元测试通过、无警告；
5. 提交 PR 并关联对应的 Issue。

---

## 本地开发环境搭建

### 前置依赖
- **操作系统**：Windows 10 / Windows 11 (x86_64)
- **Flutter SDK**：`>=3.24.0`（启用 Windows 桌面支持：`flutter config --enable-windows-desktop`）
- **Visual Studio**：Visual Studio 2022（需安装“使用 C++ 的桌面开发”工作负载）
- **Git**：最新版本
- **.NET Framework 4.0+**（用于编译单文件 C# 安装包）

### 获取源码与启动
```powershell
# 1. 克隆你的 Fork 仓库
git clone https://github.com/<your-username>/easy_tunnel.git
cd easy_tunnel\app

# 2. 安装 Dart / Flutter 依赖
flutter pub get

# 3. 运行调试版
flutter run -d windows
```

### 执行测试与静态分析
```powershell
cd easy_tunnel\app

# 静态代码检查
flutter analyze

# 运行单元测试
flutter test --no-pub
```

### 构建 Windows 安装包
1. 先构建 Flutter Windows Release 二进制：
   ```powershell
   cd easy_tunnel\app
   flutter build windows --release
   ```
2. 执行安装包编译脚本：
   ```powershell
   cd ..\installer
   .\build_installer.ps1
   # 输出产物位于: easy_tunnel\dist\EasyTunnel-Setup-v1.0.1.exe
   ```

---

## 代码规范与风格

- 遵循 Dart 官方标准风格指南（已配置 `analysis_options.yaml`）；
- 业务服务（`lib/services/`）应遵循单一职责原则，处理外部命令调用与异步数据流；
- UI 组件（`lib/ui/`）应保持清晰的组件拆分，遵循暗黑极简视觉规范（颜色取自 `lib/theme.dart`）；
- 新增核心服务必须配套单元测试（存放于 `test/` 目录下）。

---

## Git 提交信息规范 (Conventional Commits)

提交信息建议遵循 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
<type>(<scope>): <subject>

[optional body]

[optional footer(s)]
```

### 常用 Type：
- `feat`: 新增功能
- `fix`: 修复 Bug
- `docs`: 文档变动
- `style`: 代码格式优化（不影响代码运行逻辑）
- `refactor`: 重构（既不是新增功能也不是修复 Bug）
- `perf`: 性能优化
- `test`: 增加或修改测试
- `chore`: 构建系统或辅助工具的变动

**示例**：
```
feat(engine): add automatic cloudflare tunnel token sync
fix(port): resolve port collision detection on win11
docs(readme): add screenshot gallery and quick start guide
```

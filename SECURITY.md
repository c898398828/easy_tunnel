# 安全政策 (Security Policy)

## 适用版本

目前受安全支持的版本如下：

| 版本 | 是否支持安全更新 |
| :--- | :--- |
| `v1.0.x` | :white_check_mark: 当前支持 |
| `< v1.0.0` | :x: 不再支持 |

---

## 本地凭据与安全设计原则

Easy Tunnel 在设计上严格遵循以下本地数据与安全规范：
1. **凭证脱敏与本地存储**：用户的 Cloudflare API Token、ngrok Authtoken 等敏感凭据仅保存在本机 `%APPDATA%\dev.easytunnel\config.json` 或便携目录 `data/config.json` 中，**绝不上报至任何远程服务器或分析平台**。
2. **界面脱敏展示**：所有界面在展示凭证信息时均强制进行掩码脱敏（例如 `cfat****cc28`）。
3. **子进程生命周期受控**：主进程退出时执行级联树终止（`taskkill /F /T`），避免遗留无守护的隧道子进程导致公网后门风险。

---

## 报告安全漏洞

如果你发现了 Easy Tunnel 中的安全隐患或潜在漏洞（如凭据泄露风险、越权端口接管等）：
- **请勿** 直接在公共 GitHub Issues 提出安全漏洞；
- 请通过 GitHub 的 **Security Advisory (Report a vulnerability)** 渠道私密提交；
- 收到报告后，维护团队将在 48 小时内确认并评估影响范围，并在发布安全补丁后适时公布致谢。

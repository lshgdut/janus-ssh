# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Security Architecture

Janus SSH 故意 **不启用 App Sandbox**(ADR-0007),原因是:

- 需要 spawn `/usr/bin/ssh`
- 需要读 `~/.ssh/config`
- 需要访问 `ssh-agent`
- 需要 kill SSH 子进程

作为补偿:
- ✅ **Hardened Runtime** 全开(`com.apple.security.cs.*`)
- ✅ **Notarization**:`xcrun notarytool` 公证
- ✅ **签名**:`Developer ID Application`(非 App Store)
- ✅ **100% 系统 OpenSSH**:不实现 SSH 协议,不维护 OpenSSH 兼容性的负担
- ✅ **参数数组启动 SSH**:不通过 shell,无命令注入

## Reporting a Vulnerability

如果发现安全漏洞:

1. **不要**公开提 Issue
2. 发邮件给 <security@janus-ssh.example.com>(待替换为真实邮箱)
3. 包含:
   - 复现步骤
   - 影响范围
   - 建议修复(可选)

我们会在 **48 小时内** 确认,在 **7 天内** 评估严重程度,在 **30 天内** 修复严重漏洞。

## Threat Model

Janus SSH 的威胁模型:

| 攻击面 | 缓解 |
|--------|------|
| 恶意 SSH Config | 只读 ~/.ssh/config,从不修改 |
| Profile 文件被篡改 | Atomic write + .bak,损坏时回退 |
| macOS 关机数据丢失 | AppLifecycleManager 监听 willPowerOff |
| 进程泄漏 | SSHProcessManager.terminateAll(reason: .applicationShutdown) |
| Pipe buffer 阻塞 | readabilityHandler 实时消费,不用 waitUntilExit |
| 子进程残留 | SIGTERM (5s grace) → SIGKILL |

## Known Limitations

- App crash / SIGKILL 时 SSH 子进程可能残留,需要手动 `kill -9 ssh`
- App Sandbox 关闭意味着无法上架 Mac App Store
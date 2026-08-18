# ADR-0009: Always Include `-o ExitOnForwardFailure=yes`

## Status

Accepted · 2026-08-18

## Context

SSH `-L` 的行为有个微妙问题:**只有第一个 forward 失败时,ssh 才会退出**。

假设 Profile 有 3 条 forward:

```
Production
├── Forward 1: PostgreSQL ✓
├── Forward 2: Redis     ✓
└── Forward 3: API       ✗ (端口冲突 / Remote 不可达)
```

如果不加 `-o ExitOnForwardFailure=yes`:
- ssh 启动后,Forward 1, 2 成功
- Forward 3 失败但 ssh 不退出
- Janus UI 显示 ●Running
- 但实际上 API 不可达 — **错误状态**

## Decision

Janus SSH 默认 **永远** 添加 `-o ExitOnForwardFailure=yes`,不可关闭。

## Consequences

### Positive

- **状态真实反映能力**:Running = 所有 forward 都成功,Error = 至少一个失败
- **Auto Reconnect 触发更准确**:SSH 进程会真退出,而不是挂着残废
- **错误定位更清晰**:stderr 直接说"channel open failed"

### Negative

- 用户无法关闭这个 flag(故意的 — 是安全网)

## Implementation

```swift
struct SSHCommandBuilder {
    static let mandatoryFlags: [String] = [
        "-N",                                            // 不要 tty
        "-o", "ExitOnForwardFailure=yes",                 // ★ 核心安全网
        "-o", "BatchMode=yes",                           // 不提示密码
        "-o", "StrictHostKeyChecking=accept-new",        // 首次连接自动接受
        "-o", "ServerAliveInterval=60",
        "-o", "ServerAliveCountMax=3"
    ]
}
```

## Notes

OpenBSD 手册原文:

> ExitOnForwardFailure
>     Specifies whether ssh(1) should terminate the connection if it cannot set up all requested
>     dynamic, tunnel, local, and remote port forwardings.

[OpenBSD ssh_config(5)](https://man.openbsd.org/OpenBSD-7.7/ssh_config.5)
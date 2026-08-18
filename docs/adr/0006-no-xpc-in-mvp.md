# ADR-0006: No XPC / Helper in MVP

## Status

Accepted · 2026-08-18

## Context

传统 macOS 工具的最佳实践是把 SSH Process 放到 XPC Helper,这样 GUI 关闭后 Tunnel 仍运行。

但这意味着:
- XPC Protocol 定义
- Helper Bundle 工程
- Code Signing(helper 需要单独签名)
- LaunchAgent / SMAppService 注册
- Lifecycle 管理
- Debug 复杂度大幅上升

## Decision

**MVP 不引入 XPC / Helper / LaunchAgent。**

第一版架构:

```
Janus.app
    │
    ▼
Process (Foundation)
    │
    ▼
ssh
```

Quit App → stopAll → SSH Process 终止。

## When to Revisit

未来如果用户明确要求:

> "关闭 Janus GUI 后 Tunnel 继续运行"

则重构为:

```
Janus.app
    │
    │ XPC
    ▼
Janus Tunnel Service (Helper App)
    │
    ▼
ssh
```

或更进一步的:

```
SMAppService.mainApp
    │
    ▼
Janus.app (UI)
    │
    │ XPC
    ▼
SMAppService.agent
    │
    ▼
ssh
```

## Why Now Is Right

- 第一版用户大概率在 Quit 前会先 Stop All
- 开发/调试简单太多
- App 升级 / 重启时 SSH 残留是已知问题,但 MVP 不解决

## Consequences

### Positive
- **架构简单**:一个进程,一个 actor,一个 Process
- **调试容易**:lldb 直接 attach
- **代码签名简单**:只签主 App

### Negative
- 关闭 GUI 后 SSH 终止
- Crash 时 SSH 残留(只能 kill -9 SSH 手动清理)

## Related

- ADR-0002: 100% Use System OpenSSH
- ADR-0008: Tunnel Engine as独立 Swift Package(后续切换 XPC 时不影响 Engine 代码)
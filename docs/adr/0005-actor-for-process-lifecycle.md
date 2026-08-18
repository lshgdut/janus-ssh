# ADR-0005: SSHProcess is an Actor

## Status

Accepted · 2026-08-18

## Context

SSHProcess 同时受到多种事件影响:
- 用户点击 Start
- 用户点击 Stop
- 用户点击 Restart
- Auto Reconnect 调度
- App Quit / macOS 关机
- SSH 进程自然退出
- SSH 进程异常退出

如果用普通 class + lock,容易产生竞态:

```
Thread A: stop()        → process.terminate()
Thread B: restart()     → process.run()
Thread C: process exited → 回调 onExit
```

## Decision

```swift
actor SSHProcess {
    // 所有 Start / Stop / Terminate 调用串行化
}
```

## Consequences

### Positive
- **状态串行化**:actor 保证同一时刻只有一个调用在执行
- **编译期安全**:Swift 6 strict concurrency 强制 actor 隔离

### Negative
- 调用方必须 `await proc.xxx()`,即使是看起来"立即"的 get
- 跨 actor 状态读取需要显式 await

## Implementation Pattern

```swift
actor SSHProcess {
    private var process: Process?

    func start() async throws {
        // 检查 process == nil (actor 串行化保证这里安全)
        guard process == nil else { throw SSHProcessError.alreadyRunning }
        let p = Process()
        p.terminationHandler = { [weak self] proc in
            // terminationHandler 在子线程触发 — 需要 hop 回 actor
            Task { await self?.handleTermination(proc) }
        }
        try p.run()
        self.process = p
    }
}
```

## Related

- ADR-0002: 100% Use System OpenSSH
- `Sources/JanusSSHTunnelEngine/SSH/SSHProcess.swift`
- `Sources/JanusSSHTunnelEngine/SSH/SSHProcessManaging.swift`
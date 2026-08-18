# ADR-0004: One Profile = One SSH Process = N Port Forwards

## Status

Accepted · 2026-08-18

## Context

用户创建 Profile 时,有 N 个 forward (-L) 需要启。两种映射:

**Option A**: 每个 Forward 一个 SSH Process
**Option B**: 整个 Profile 一个 SSH Process

## Decision

**Option B** — 一个 Profile = 一个 SSH Process = N 个 Port Forward。

```
Production (1 ssh)
   ├── -L 15432:10.20.0.15:5432
   ├── -L 16379:10.20.0.16:6379
   └── -L 18080:10.20.0.17:8080

Staging (1 ssh)
   ├── -L 25432:10.30.0.15:5432
   └── -L 28080:10.30.0.16:8080
```

## Rationale

### Performance
- 启动 1 个 SSH 连接比 3 个快很多(认证开销)
- Network connection 数量减半

### UX
- 一个 Profile 是一个"组" — 用户认知模型
- Start All / Stop All 一次操作

### 安全
- 一个 Profile 一个 agent forwarding 决定

## Example

```swift
let profile = Profile(
    name: "Production",
    sshHostAlias: "production",
    forwards: [
        PortForward(localHost: "127.0.0.1", localPort: 15432,
                    remoteHost: "10.20.0.15", remotePort: 5432, label: "postgres"),
        PortForward(localHost: "127.0.0.1", localPort: 16379,
                    remoteHost: "10.20.0.16", remotePort: 6379, label: "redis"),
        PortForward(localHost: "127.0.0.1", localPort: 18080,
                    remoteHost: "10.20.0.17", remotePort: 8080, label: "http")
    ],
    behavior: ...
)
```

SSH 命令:

```
ssh -N -o ExitOnForwardFailure=yes \
    -L 127.0.0.1:15432:10.20.0.15:5432 \
    -L 127.0.0.1:16379:10.20.0.16:6379 \
    -L 127.0.0.1:18080:10.20.0.17:8080 \
    production
```

## Forward Type Extensibility

未来加 `-R` (RemoteForward) 和 `-D` (DynamicForward):

```swift
enum ForwardKind {
    case local(PortForward)   // -L
    case remote(PortForward)  // -R (未来)
    case dynamic(UInt16)       // -D (未来)
}
```

Profile 内可以有混合类型,但仍然是 **一个 SSH Process**。

## Consequences

### Positive
- 用户认知一致
- 性能好
- Auto Reconnect 一次重启全部恢复

### Negative
- 跨 forward 不能独立 stop(必须整组重启)
- Profile 内端口冲突难定位(实际我们已经校验)

## Related

- ADR-0009: ExitOnForwardFailure(强制全有或全无)
- `Sources/JanusSSHTunnelEngine/SSH/SSHCommandBuilder.swift`
- `Sources/JanusSSHTunnelEngine/Domain/Profile.swift`
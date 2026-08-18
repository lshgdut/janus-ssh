# ADR-0010: Use `ssh -G` for Host Resolution

## Status

Accepted · 2026-08-18

## Context

Janus 需要在 SSH Hosts 页面展示每个 host 的完整配置:hostname / port / user / identity / proxyJump。

两种方式:
- **A 自己解析** `~/.ssh/config`
- **B 调用** `ssh -G <alias>` 让 OpenSSH 解析

## Decision

采用 **B** — 调用 `ssh -G <alias>` 拿最终配置。

## Rationale

```
~/.ssh/config
    ↓
OpenSSH (处理 Host / Match / Include)
    ↓
ssh -G production
user root
hostname 10.10.0.10
port 22
identityfile ~/.ssh/id_ed25519
proxyjump bastion
...
    ↓
Janus 解析 stdout
```

而不是:

```
~/.ssh/config
    ↓
Janus 自己实现 Host / Match / Include 语义  ← 重新发明轮子
```

## Implementation

```swift
let proc = try SSHProcess(
    executable: URL(fileURLWithPath: "/usr/bin/ssh"),
    arguments: ["-G", "production"]
)
try await proc.start()
let stdout = try await readUntilExit(proc)
```

输出格式:`key value\n`,解析后构造 `ResolvedHostConfig`。

## What About Include?

OpenSSH 自动递归处理 `Include ~/.ssh/conf.d/*`。我们让 `ssh -G` 处理。

如果未来需要列出所有 host alias(不止 first match),则:
- **Discovery** 用简化版 `SSHConfigParser`(只取 alias + 必要字段,不解析语义)
- **Resolution** 仍用 `ssh -G`

## Consequences

### Positive
- **零 SSH Config 解析代码** — 不维护 Host / Match 兼容性
- **未来 OpenSSH 加新特性自动支持**

### Negative
- `ssh -G` 调用 spawn ssh(每次 Refresh 都要跑一次)
- 对每个 host 多次 spawn — 性能可以接受(developer tool,几十个 host)

## Related

- ADR-0002: 100% Use System OpenSSH
- `Sources/JanusSSHTunnelEngine/Services/SSHConfigProviding.swift`
- `Sources/JanusSSHTunnelEngine/Services/SSHConfigParser.swift`
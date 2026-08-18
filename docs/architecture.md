# Janus SSH — Architecture

> 一句话:**Janus SSH = 原型定义的 6 个屏幕 × 三层架构 × 一个 Swift Package 化的 Tunnel Engine × 不实现 SSH 的硬性原则**

---

## 三层架构

```
┌─────────────────────────────────────────────┐
│                 Janus App                   │
│                                             │
│  SwiftUI                                    │
│      │                                      │
│      ▼                                      │
│  Presentation                              │
│      │                                      │
│      ▼                                      │
│  Application                               │
│      │                                      │
│      ├── ProfileManager                     │
│      ├── TunnelManager                      │
│      ├── SSHHostManager                     │
│      └── ReconnectController                │
│                                             │
│      ▼                                      │
│  Infrastructure                            │
│      │                                      │
│      ├── SSHConfigService                   │
│      ├── SSHProcessManager                  │
│      ├── PortChecker                        │
│      ├── ProfileRepository                  │
│      └── LogStore                           │
│                                             │
└───────────────┬─────────────────────────────┘
                │
        ┌───────┴─────────┐
        ▼                 ▼
   macOS Frameworks    /usr/bin/ssh
```

## 核心约束

```
View ──► ViewModel ──► Manager ──► Service ──► Infrastructure
  └─────────────── Observation (read-only) ───────────────┘
```

View 永远不能直接调用 SSHProcess。所有路径必须经过 TunnelManager。

## Tunnel Engine 作为独立 Swift Package

`JanusSSHTunnelEngine` 是独立 Swift Package:
- 可以在 macOS App 之外独立测试
- 未来抽出 CLI(`janus` 命令行)直接复用
- 未来切到 XPC Helper 时只换 SSHProcess 的 IPC 通道

## Domain 隔离

```
Profile(持久化配置)
   ├── sshHost
   ├── Forward 1, 2, 3
   └── Behavior (enabled / autoReconnect / autoStart)
   
Tunnel(运行时)
   ├── profileSnapshot  ← 启动时的不可变副本
   ├── state            ← stopped/starting/running/stopping/error/reconnecting
   ├── pid
   ├── startedAt
   ├── stoppedAt
   └── lastError
```

Profile 和 Tunnel **严格解耦**:
- 改 Profile 不影响已运行的 Tunnel
- 启动失败不污染 Profile 数据
- Persistence 只关心 Profile,Tunnel 状态不进 profiles.json
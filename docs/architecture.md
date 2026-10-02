# Janus SSH — Architecture

> 一句话:**Janus SSH = 7 个屏幕 × Command/Service/DAO 四层 × 一个 Swift Package 化的 Tunnel Engine × 不实现 SSH 的硬性原则**

---

## 四层架构 (v0.4.0+)

```
┌─────────────────────────────────────────────┐
│                  Janus App                  │
│                                             │
│  SwiftUI                                    │
│      │  @Environment(AppContainer.self)     │
│      ▼                                      │
│  AppContainer (facade)                      │
│      │  services: ServicesContainer         │
│      ▼                                      │
│  ServicesContainer (engine, @MainActor)     │
│      │                                      │
│      ├── ProfileService                     │
│      ├── TunnelService                      │
│      ├── ReconnectService                   │
│      ├── ManagedPIDService                  │
│      ├── SSHConfigManager                   │
│      └── SettingsService                    │
│                                             │
│      ▼                                      │
│  DAOs (actor, per-aggregate)                │
│      │                                      │
│      ├── ProfileDAO   → profiles.json       │
│      ├── SettingsDAO  → settings.json       │
│      └── ManagedPIDDAO → managed_pids.json  │
│                                             │
│  Infrastructure                            │
│      ├── SSHCommandBuilder                  │
│      ├── SSHProcess / SSHProcessManager     │
│      ├── PortChecker                        │
│      ├── AtomicFileStore                    │
│      ├── JSONMigrator                       │
│      └── SSHConfigProviding                 │
│                                             │
└───────────────┬─────────────────────────────┘
                │
        ┌───────┴─────────┐
        ▼                 ▼
   macOS Frameworks    /usr/bin/ssh
```

### 分层职责

| 层 | 职责 | 依赖 | 隔离 |
|---|---|---|---|
| **Domain** | 数据结构 + 跨服务事件 | 无 | Sendable |
| **Persistence (DAO)** | 文件 I/O、原子写、envelope、迁移 | Domain | actor |
| **Services** | 业务逻辑、状态机、事件发布 | DAO, SSH, Domain | `@MainActor @Observable` (状态型) 或 `actor` (纯逻辑型) |
| **App (AppContainer)** | service 聚合 + DI 入口 + UI 状态 | Services | MainActor |

### Compat shims (过渡期)

v0.4.0 重构引入新架构,但保留 v0.3.x 的 compat shim 以避免一次性大改 App 端 7 个 view + preview seed:

- `JanusSSH/App/SSHHostManager.swift`(→ `services.sshConfigManager`)
- `JanusSSH/App/SettingsManager.swift`(→ `services.settingsService`)
- `JanusSSHTunnelEngine/Services/ReconnectController.swift`(→ `services.reconnectService`)
- `JanusSSHTunnelEngine/Tunnel/TunnelManager.swift`(→ `services.tunnelService`)
- `JanusSSHTunnelEngine/Persistence/JSONProfileRepository.swift`(→ `ProfileDAO`)
- `JanusSSHTunnelEngine/Settings/JSONSettingsRepository.swift`(→ `SettingsDAO`)
- `JanusSSHTunnelEngine/Services/ManagedPIDStore.swift`(→ `ManagedPIDService`)

后续清理 PR 会 sed-rename view 调用点 + 删除 shim 文件。

---

## 主要决策

详见 `docs/adr/`:
- ADR-0001 ~ 0010 — 既有决策
- **ADR-0011** Command / Service / DAO 分层
- **ADR-0012** 统一 `AppError`
- **ADR-0013** 声明式 `JSONMigrator`

## 错误流

```
Domain Error (Sendable + LocalizedError)
    ↓
Service throws AppError
    ↓
AppContainer catches → AppError.errorDescription → UI 文案
```

详见 ADR-0012。

## 持久化流

```
profileRepo.save(profiles)
    ↓
AtomicFileStore.write (tmp → fsync → rename)
    ↓
backup/profile-<ISO8601>.json (滚动 10 个)
```

详见 `ProfileDAO.swift` / `JSONMigrator.swift`。

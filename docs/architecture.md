# Janus SSH — Architecture

> **Status:** v0.4.0 — Tauri 2 rewrite (Rust + React). Swift implementation preserved on `archive/swift-legacy` branch.

## Three-layer backend

```
┌─────────────────────────────────────────────┐
│               Tauri Commands                │  ← IPC layer (commands/*.rs)
│                                               │
│   list_profiles, start_tunnel, get_settings … │
└───────────────┬─────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────┐
│               Services                       │  ← business logic
│                                               │
│   ProfileService, TunnelService,             │
│   ReconnectService, ManagedPIDService,       │
│   SSHConfigService, SettingsService          │
└───────────────┬─────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────┐
│               DAOs                           │  ← persistence
│                                               │
│   ProfileDAO  → profiles.json               │
│   SettingsDAO → settings.json                │
│   ManagedPIDDAO → managed_pids.json          │
│                                               │
│   All wrapped by AtomicJsonStore:            │
│   - atomic write (tmp + fsync + rename)      │
│   - backup rotation (rolling 10)             │
│   - schema envelope (declarative migration)  │
└─────────────────────────────────────────────┘
```

## Layer responsibilities

| Layer | Responsibility | Isolation |
|---|---|---|
| **Domain** (`domain.rs`) | Data structures + cross-service events | Sendable |
| **Persistence** | File I/O, atomic write, envelope, migration | `AtomicJsonStore` |
| **Services** | Business logic, state machine, event publishing | `Arc<RwLock<…>>` |
| **Commands** | IPC handlers — thin wrappers around services | Sync → async via Tauri |
| **SSH** (`ssh/`) | `/usr/bin/ssh` invocation + event streaming | `tokio::process` |

## Frontend

React 18 + TypeScript + Vite + Tailwind + TanStack Query. State flow:

```
[ Tauri Command ] → [ TanStack Query cache ] → [ React component ]
                                                       │
                                                       ▼
                                            [ invoke() mutation ] ──┐
                                                                    │
        ┌───────────────────────────────────────────────────────────┘
        ▼
[ Tauri Command ] → [ Service ] → [ DAO ] → [ Atomic write ] → [ disk ]
```

## Key invariants (preserved from Swift engine)

1. **`userRequestedStop` defense** — `stop()` sets the flag; observation task checks it on exit to prevent auto-reconnect from re-launching a user-stopped tunnel
2. **`generations[id]` counter** — bumped at `start()`; observation task drops stale events from previous processes
3. **`Tunnel.markStopping()/markStopped()` single convention** — all stop-path state writes go through these helpers
4. **`stopAll()` preserves diagnostics** — `.error` and `.stopped` tunnels keep their `lastError` / `stoppedAt`
5. **Atomic JSON persistence** — `tmp + fsync + rename` + rolling backups, never corrupt on crash
6. **Schema envelope** — `ProfileEnvelope { version, profiles }`; future migrations via `SchemaVersion` chain

## Cross-cutting concerns

- **Errors:** `AppError` (thiserror enum, `Serialize + Deserialize`) → flat string for IPC transport
- **Persistence:** `AtomicJsonStore` with per-path `Mutex` for concurrent writes
- **Process supervision:** `SshProcessManager` tracks live PIDs in `OSAllocatedUnfairLock`-equivalent `Mutex` for sync `terminate_all_now()`
- **i18n:** `i18next` with `zh-CN` and `en` catalogs

See `docs/adr/` for the reasoning behind each layer.

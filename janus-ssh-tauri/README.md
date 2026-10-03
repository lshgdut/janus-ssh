# Janus SSH — Tauri Rewrite (v0.4.0+)

A complete rewrite of `janus-ssh` using **Tauri 2** (Rust + React 18 + Vite + TypeScript).

This project lives alongside the legacy Swift/macOS app at `/Users/hua/Desktop/01github/lshgdut/janus-ssh/`. During the migration window, both apps coexist; the Tauri version is the strategic direction.

## Why Tauri

| | Swift/macOS | Tauri (Rust + Web) |
|---|---|---|
| **Platforms** | macOS only | macOS, Windows, Linux |
| **UI** | SwiftUI (native) | React + Tailwind (web) |
| **Bundle size** | ~10 MB | ~5 MB |
| **Process management** | AppKit + Foundation | tokio + std::process |
| **Persistence** | AtomicFileStore | AtomicJsonStore (same pattern) |
| **Architecture** | Command/Service/DAO | Command/Service/DAO (same) |

## Status

| Stage | Status |
|---|---|
| T1: Tauri scaffold | ✅ (this PR) |
| T2: Rust layered backend | ✅ (this PR) |
| T3: Profile/Settings DAOs + Services | ✅ (this PR) |
| T4: SSH tunnel lifecycle | ✅ (this PR) |
| T5: React UI shell + theme | ⏳ (follow-up) |
| T6: Profile list + editor | ⏳ (follow-up) |
| T7: Hosts + settings + tunnel log views | ⏳ (follow-up) |
| Menu bar popover (tray-icon) | ⏳ |
| Auto-launch (tauri-plugin-autostart) | ⏳ |
| Notifications (tauri-plugin-notification) | ⏳ |
| DMG / Homebrew Cask / Linux packaging | ⏳ |

## Tech Stack

- **Backend:** Rust 1.85+, Tauri 2.1, tokio, serde, thiserror, tracing
- **Frontend:** React 18, TypeScript 5.6, Vite 5, Tailwind CSS, Radix UI, TanStack Query
- **State management:** TanStack Query (server state) + Zustand (UI state)
- **i18n:** i18next (zh-CN, en)
- **Persistence:** JSON files (atomic write + envelope + backup rotation)
- **Process management:** tokio::process + custom SSH subprocess supervision

## Architecture

```
janus-ssh-tauri/
├── src/                              # React frontend (Vite)
│   ├── components/                   # shadcn/ui primitives
│   ├── features/{profiles,hosts,settings,tunnel-log}/
│   ├── lib/
│   │   ├── api/                      # Typed Tauri command wrappers
│   │   ├── query/                    # TanStack Query hooks
│   │   └── schemas/                  # zod schemas
│   ├── i18n/                         # i18next catalogs
│   └── hooks/
└── src-tauri/                        # Rust backend
    ├── Cargo.toml
    ├── tauri.conf.json
    ├── capabilities/default.json
    └── src/
        ├── lib.rs                    # run() entry + plugin wiring
        ├── main.rs                   # binary entry
        ├── error.rs                  # AppError (thiserror)
        ├── store.rs                  # AppState (Arc<Database> + service refs)
        ├── settings.rs               # AppSettings struct
        ├── schema_version.rs         # declarative schema migration
        ├── persistence/
        │   ├── atomic_json_store.rs  # atomic write + backup + envelope
        │   ├── profile_dao.rs        # ProfileDAO protocol + JSON impl
        │   ├── settings_dao.rs       # SettingsDAO protocol + JSON impl
        │   └── managed_pid_dao.rs    # ManagedPIDDAO protocol + JSON impl
        ├── services/
        │   ├── services_container.rs # service aggregator
        │   ├── profile_service.rs    # @MainActor @Observable state
        │   ├── tunnel_service.rs     # tunnel lifecycle orchestrator
        │   ├── reconnect_service.rs  # backoff scheduling
        │   ├── managed_pid_service.rs # orphan process sweep
        │   ├── ssh_config_service.rs # ~/.ssh/config discovery + tests
        │   └── settings_service.rs   # settings state + diff-then-write
        ├── commands/
        │   ├── mod.rs
        │   ├── profile.rs
        │   ├── tunnel.rs
        │   ├── ssh_config.rs
        │   └── settings.rs
        ├── ssh/
        │   ├── ssh_command_builder.rs
        │   ├── ssh_process.rs
        │   └── ssh_process_manager.rs
        └── lifecycle.rs              # App startup/shutdown
```

## Development

```bash
# Install dependencies
pnpm install

# Run in dev mode (hot reload)
pnpm tauri:dev

# Build release binary
pnpm tauri:build

# Run Rust tests
cd src-tauri && cargo test

# Run frontend tests (when added)
pnpm test
```

## Data Compatibility with Swift App

JSON file format is **backward-compatible** with the Swift v0.3.1 app:
- Same path: `~/Library/Application Support/top.lshgdut.janus-ssh/`
- Same files: `profiles.json`, `settings.json`, `managed_pids.json`
- Same `ProfileEnvelope { version: 1, profiles: [...] }` envelope shape

Users can switch between the Swift app and the Tauri app without losing data.

## License

MIT

# Janus SSH

A menu bar SSH tunnel manager built with **Tauri 2** (Rust + React).

> **Note:** As of v0.4.0, janus-ssh is a complete rewrite from the original Swift/macOS app. The legacy Swift implementation is preserved on the `archive/swift-legacy` branch and tagged `swift-v0.3.1-final` for reference.

## What it does

Janus SSH lets you manage **SSH port-forward profiles** — each profile maps to one SSH process that forwards N local ports to remote endpoints. Key features:

- **Profile-centric UI** — one profile = one SSH process = N port forwards
- **Visual `~/.ssh/config` editor** — discover hosts (with `Include` recursion), test connection per host
- **Auto-reconnect** — exponential backoff (1s → 30s) on SSH exit
- **Orphan sweep** — App restart SIGKILLs stale SSH processes from previous session
- **Theme** — system / light / dark via Tauri's window theming
- **Cross-platform** — macOS, Windows, Linux (single binary)
- **Atomic JSON persistence** — backward-compatible with the legacy Swift app

## Tech stack

- **Backend:** Rust 1.85+, Tauri 2.1, tokio, serde, thiserror, tracing
- **Frontend:** React 18, TypeScript 5.6, Vite 5, Tailwind CSS, Radix UI, TanStack Query
- **State management:** TanStack Query (server state) + Zustand (UI state)
- **i18n:** i18next (zh-CN, en)
- **Persistence:** JSON files (atomic write + envelope + backup rotation)
- **Process management:** tokio::process + custom SSH subprocess supervision

## Architecture

Three-layer backend (Command/Service/DAO) with React frontend:

```
src-tauri/src/                  Rust backend
├── lib.rs                      # run() entry + plugin wiring + setup
├── error.rs                    # AppError (thiserror)
├── settings.rs                 # AppSettings struct
├── schema_version.rs           # declarative migration envelope
├── domain.rs                   # Profile / Tunnel / SshHost / ManagedPID
├── persistence/                # DAO layer
│   ├── atomic_json_store.rs    # atomic write + backup + envelope
│   ├── profile_dao.rs
│   ├── settings_dao.rs
│   └── managed_pid_dao.rs
├── services/                   # business logic
│   ├── services_container.rs   # service aggregator
│   ├── profile_service.rs
│   ├── tunnel_service.rs       # lifecycle + state machine
│   ├── reconnect_service.rs    # backoff scheduling
│   ├── managed_pid_service.rs  # orphan process sweep
│   ├── ssh_config_service.rs   # ~/.ssh/config parsing + tests
│   └── settings_service.rs
├── commands/                   # Tauri IPC handlers
│   ├── profile.rs
│   ├── tunnel.rs
│   ├── ssh_config.rs
│   └── settings.rs
└── ssh/                        # SSH subprocess layer
    ├── ssh_command_builder.rs
    └── ssh_process_manager.rs

src/                            React frontend
├── main.tsx                    # bootstrap (TanStack Query + i18n)
├── App.tsx                     # sidebar + views
├── components/                 # shadcn/ui primitives
├── features/                   # profiles / hosts / settings / tunnel-log
├── lib/
│   ├── api/                    # typed Tauri command wrappers
│   ├── query/                  # TanStack Query hooks
│   └── schemas/                # zod schemas
└── i18n/                       # i18next catalogs (en, zh)
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

### Prerequisites

- **Node.js** 22+
- **Rust** 1.85+ (use `rustup`)
- **pnpm** 10+
- **macOS:** Xcode Command Line Tools (`xcode-select --install`)
- **Linux:** `webkit2gtk-4.1`, `libayatana-appindicator3-dev`, `librsvg2-dev`
- **Windows:** WebView2 (preinstalled on Windows 11), Visual Studio Build Tools

## Data locations

JSON files live in `app_data_dir`:

| Platform | Path |
|---|---|
| macOS | `~/Library/Application Support/top.lshgdut.janus-ssh/` |
| Linux | `~/.local/share/top.lshgdut.janus-ssh/` |
| Windows | `%APPDATA%\top.lshgdut.janus-ssh\` |

Files: `profiles.json`, `settings.json`, `managed_pids.json`, `backups/`.

## Status

| Stage | Status |
|---|---|
| T1: Tauri scaffold | ✅ |
| T2: Rust layered backend (Command/Service/DAO) | ✅ |
| T3: Profile/Settings/ManagedPID DAOs + Services | ✅ |
| T4: SSH tunnel lifecycle (TunnelService + ReconnectService + ManagedPIDService) | ✅ |
| T5: React UI shell + theme + i18n | ✅ (basic) |
| T6: Profile list + editor | ✅ (list) / ⏳ (editor form) |
| T7: Hosts + settings + tunnel log views | ⏳ |
| Menu bar popover (tray-icon) | ⏳ |
| Auto-launch (tauri-plugin-autostart) | ⏳ |
| Notifications (tauri-plugin-notification) | ⏳ |
| DMG / Homebrew Cask / Linux packaging | ⏳ |

## Migration from Swift app

JSON file format is **backward-compatible** with the legacy Swift v0.3.1 app:
- Same `app_data_dir` path
- Same files: `profiles.json`, `settings.json`, `managed_pids.json`
- Same `ProfileEnvelope { version, profiles }` envelope shape

You can switch between the Swift app and the Tauri app without losing data. (Once you switch to Tauri, going back to Swift would require downgrading the JSON envelope — out of scope here.)

## License

MIT

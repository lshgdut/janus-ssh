# Janus SSH

> 原生 macOS SSH Tunnel Manager — `~/.ssh/config` 的可视化前端

**v0.1 prototype**

---

## 设计原则

1. **不实现 SSH** — 100% 复用系统 `/usr/bin/ssh`
2. **不修改 `~/.ssh/config`** — 只读,数据落在 `~/Library/Application Support/com.lshgdut.janus-ssh/`
3. **一个 Profile = 一个 SSH Process = N 个 Port Forward**

---

## 仓库结构

```
janus-ssh/
├── JanusSSHTunnelEngine/   # 独立 Swift Package,纯 Swift
│   ├── Sources/JanusSSHTunnelEngine/
│   │   ├── Domain/         # Profile, PortForward, Tunnel, TunnelState, TunnelError
│   │   ├── Validation/     # ProfileValidator, ValidationIssue
│   │   ├── Persistence/    # AtomicFileStore, JSONProfileRepository, SchemaVersion
│   │   ├── Settings/       # AppSettings, BackoffPolicy, JSONSettingsRepository
│   │   ├── SSH/            # SSHCommandBuilder, SSHProcess, SSHProcessManaging
│   │   ├── Tunnel/         # TunnelManager
│   │   ├── Network/        # PortChecking, TCPPortChecker
│   │   └── Services/       # SSHHostManager, ReconnectController, TunnelLogStore
│   ├── Tests/              # XCTest
│   └── verify/             # 独立可执行验证(CommandLineTools 环境)
│
├── JanusSSH/               # macOS App target (Xcode)
│   ├── App/                # JanusSSHApp, AppContainer, AppLifecycleManager
│   ├── Presentation/       # SwiftUI Views
│   │   ├── Navigation/     # RootView, SidebarView
│   │   ├── Profiles/      # ProfileListView, ProfileEditorView, ProfileRunningView
│   │   ├── Hosts/         # SSHHostListView
│   │   ├── Logs/          # TunnelLogView
│   │   ├── Settings/      # SettingsView
│   │   └── MenuBar/       # MenuBarView
│   └── Resources/          # Info.plist, JanusSSH.entitlements
│
├── tools/integration-tests/ # Docker sshd 集成测试
│
├── docs/
│   ├── architecture.md     # 整体架构
│   ├── tunnel-engine.md    # Engine 详解
│   ├── persistence.md      # Persistence 详解
│   └── adr/                # 10 个 ADR
│
└── scripts/
    ├── build.sh
    ├── test.sh
    └── release.sh
```

---

## 开发命令

### Tunnel Engine(可在 CommandLineTools 中跑)

```bash
cd JanusSSHTunnelEngine

# 编译 library
swift build

# 在 Xcode 16+ 中跑 XCTest(需 Xcode)
swift test

# CommandLineTools 下用独立验证可执行
swiftc -parse-as-library -o /tmp/janus_verify \
  Sources/JanusSSHTunnelEngine/Domain/*.swift \
  Sources/JanusSSHTunnelEngine/Validation/*.swift \
  Sources/JanusSSHTunnelEngine/Persistence/*.swift \
  Sources/JanusSSHTunnelEngine/Settings/*.swift \
  Sources/JanusSSHTunnelEngine/SSH/*.swift \
  Sources/JanusSSHTunnelEngine/Tunnel/*.swift \
  Sources/JanusSSHTunnelEngine/Network/*.swift \
  Sources/JanusSSHTunnelEngine/Services/*.swift \
  verify/verify.swift
/tmp/janus_verify
```

### macOS App(需要在 Xcode 16+ 中)

```bash
xed .                              # 打开 Xcode
# Cmd+R 跑 App
# Cmd+U 跑测试
```

---

## 关键 ADR(见 `docs/adr/`)

1. `0001-native-swiftui.md` — SwiftUI + Observation
2. `0002-use-system-openssh.md` — 不实现 SSH,100% 用 `/usr/bin/ssh`
3. `0003-profile-json-storage.md` — Codable + JSON + atomic rename
4. `0004-profile-one-ssh-process.md` — 1 Profile = 1 SSH Process = N Forwards
5. `0005-actor-for-process-lifecycle.md` — SSHProcess 为 actor
6. `0006-no-xpc-in-mvp.md` — MVP 不引入 Helper/LaunchAgent
7. `0007-no-app-sandbox.md` — 必须关闭 Sandbox
8. `0008-tunnel-engine-as-package.md` — Engine 独立 Swift Package
9. `0009-exit-on-forward-failure.md` — 默认 `-o ExitOnForwardFailure=yes`
10. `0010-use-ssh-G-for-resolution.md` — Host 解析交给 `ssh -G`

---

## Roadmap

| Milestone | 状态 | 内容 |
|-----------|------|------|
| M1 — Domain Model | ✅ | Profile / PortForward / Tunnel / Validator |
| M2 — Persistence | ✅ | AtomicFileStore / Repository / Backup |
| M3 — SSH Engine | ✅ | SSHCommandBuilder / SSHProcess |
| M4 — TunnelManager | ✅ | State machine / PortChecker |
| M5 — SSH Config | ✅ | SSHConfigParser / discoverHosts / ssh -G |
| M6 — Reconnect | ✅ | ReconnectController / Backoff |
| M7-M9 — SwiftUI + macOS | ✅ | 6 个屏幕 + MenuBar + Settings + Launch at Login |
| M10 — Release | ⏳ | Hardened Runtime / Notarization / DMG / Homebrew Cask |

---

## License

MIT(待定)
# ADR-0008: Tunnel Engine as Independent Swift Package

## Status

Accepted · 2026-08-18

## Context

Janus SSH 的核心能力(SSH Process 管理 / Tunnel 编排 / Profile 验证 / Persistence)与 UI 完全无关。

## Decision

把 `JanusSSHTunnelEngine` 拆成 **独立 Swift Package**:
- 自己的 `Package.swift`
- 无 SwiftUI 依赖
- 可独立 build / test
- macOS App 只 import 这个 Package

## Repository Structure

```
janus-ssh/
├── JanusSSHTunnelEngine/    ← Swift Package
│   ├── Package.swift
│   ├── Sources/JanusSSHTunnelEngine/
│   │   ├── Domain/         (Profile, PortForward, Tunnel, ...)
│   │   ├── Validation/
│   │   ├── Persistence/    (AtomicFileStore, JSONProfileRepository)
│   │   ├── Settings/       (AppSettings, JSONSettingsRepository)
│   │   ├── SSH/            (SSHCommandBuilder, SSHProcess)
│   │   ├── Tunnel/         (TunnelManager)
│   │   ├── Network/        (PortChecker)
│   │   └── Services/       (ReconnectController, SSHConfigParser, ...)
│   └── Tests/JanusSSHTunnelEngineTests/
│
└── JanusSSH/                 ← Xcode project (macOS App)
    ├── JanusSSHApp.swift
    ├── App/                 (AppContainer, AppLifecycleManager, ...)
    └── Presentation/         (SwiftUI Views)
```

## Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JanusSSHTunnelEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JanusSSHTunnelEngine", targets: ["JanusSSHTunnelEngine"])
    ],
    targets: [
        .target(name: "JanusSSHTunnelEngine", path: "Sources/JanusSSHTunnelEngine"),
        .testTarget(name: "JanusSSHTunnelEngineTests",
                    dependencies: ["JanusSSHTunnelEngine"],
                    path: "Tests/JanusSSHTunnelEngineTests")
    ]
)
```

## Consequences

### Positive
- **CLI 化**:未来 `janus` 命令行工具直接 `import JanusSSHTunnelEngine`
- **测试独立**:`swift test` 在 Package 目录内就能跑
- **XPC 切换**:未来加 Helper 时,Engine 不动,只换 SSHProcess 的 IPC 通道
- **CI 加速**:Engine 测试不需要 build macOS App

### Negative
- 两个 build 系统(Package.swift + Xcode project)
- 跨 Package 边界需要严格 Sendable 标注

## Related

- ADR-0006: No XPC in MVP
- `Package.swift`
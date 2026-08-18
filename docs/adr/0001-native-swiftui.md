# ADR-0001: Native SwiftUI + Observation

## Status

Accepted · 2026-08-18

## Context

构建 macOS UI 有多种方案:Tauri / Electron / SwiftUI / AppKit。

## Decision

使用 **SwiftUI + Observation**(`@Observable` macro)。

## Rationale

| 维度 | SwiftUI | Tauri | Electron |
|------|---------|-------|----------|
| 与 macOS 集成 | 原生 | WebView 桥接 | WebView 桥接 |
| Menu Bar / Login Item | `MenuBarExtra` 一行 | 需要专门插件 | 需要专门模块 |
| Process 启动 | `Process()` 直接调 | Tauri Command + IPC | Node child_process |
| Notification | `UNUserNotificationCenter` | 插件 | 插件 |
| 性能 | 优 | 良 | 良 |
| 学习曲线 | SwiftUI 独有 | 熟悉 Web | 熟悉 Web |
| 体积 | 极小 | 含 WebView | 含 Chromium |

Janus SSH 核心能力是 **macOS Native**:Process / OpenSSH / Keychain / Menu Bar / Login Item / Notification,全部需要直接 macOS API。引入 Web Runtime 会增加 IPC 层。

## Stack 具体选择

- **macOS 14+**(最低支持)
  - `MenuBarExtra` `.window` style 仅 15+
  - `@Observable` macro GA 在 14+
  - Swift 6 strict concurrency
- **`@Observable`** 而非 `ObservableObject`
  - Apple 官方推荐(macOS 14+)
  - 自动依赖追踪
  - 更细粒度更新
- **不用第三方状态管理框架**(Combine / TCA / SwiftUI-Redux)
  - 单文件 App 不需要

## Consequences

### Positive
- 体积小(< 5MB)
- 启动快
- 与系统 UI 风格统一
- 无 IPC 开销

### Negative
- macOS 14 以下不支持
- SwiftUI 某些 API 仍不稳定(如 List 在 macOS 上的 selection 行为)
- 必须 Swift 开发

## Alternatives Considered

- **Tauri**:Web 渲染 + Rust 后端。引入 WebView layer,且 macOS Native API 需要 plugin
- **Electron**:同 Tauri,但更重(100MB+,Chromium)
- **AppKit + SwiftUI 混合**:复杂页面用 AppKit。对 Janus 不必要
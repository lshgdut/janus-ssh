import Foundation

/// Tunnel 在 TunnelManager 中的实时状态。
///
/// 状态机:
/// ```
/// stopped → starting → running → stopping → stopped
///              ↑                       │
///              └─ reconnecting(异常退出) ┘
///              ↓
///            error
/// ```
public enum TunnelState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case reconnecting
    case stopping
    case error
}

/// Process 终止原因 — 用于决定是否触发 Auto Reconnect。
///
/// 关键区分:`userRequested` 和 `applicationShutdown` 都**禁止**重连,
/// `processExited` 和 `startupFailure` 才允许重连。
public enum TerminationReason: Sendable, Equatable, Hashable {
    case userRequested
    case processExited
    case applicationShutdown
    case startupFailure
}
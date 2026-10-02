import Foundation

/// TunnelService 发布的实时事件 — UI / 日志订阅者通过 `TunnelService.observe(id:)`
/// 拿到的统一流。
///
/// 关键设计:
/// - `Sendable`:actor 边界上可跨隔离域投递,不需要 `MainActor.run`。
/// - `stateChanged(Tunnel)` 携带完整 Tunnel 快照,订阅者用 `tunnel.id` 匹配。
/// - `logLine` / `exited` 显式带 `profileID`,避免订阅者再查 tunnels[id]。
public enum TunnelEvent: Sendable {
    case stateChanged(Tunnel)
    case logLine(profileID: UUID, line: String)
    case exited(profileID: UUID, reason: TerminationReason, code: Int32?, signal: Int32?)
}

extension TunnelEvent {
    /// 事件所属的 profile id — 订阅者用来定位是哪条 tunnel 发生了变化。
    public var profileID: UUID {
        switch self {
        case .stateChanged(let t): return t.profileSnapshot.id
        case .logLine(let id, _): return id
        case .exited(let id, _, _, _): return id
        }
    }
}

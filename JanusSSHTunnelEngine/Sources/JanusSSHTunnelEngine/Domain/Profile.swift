import Foundation

/// Profile 是 Janus 用户创建的"一组 SSH Tunnel 配置"。
///
/// 一个 Profile = 一个 SSH Process = N 个 Port Forward。
///
/// Profile 故意不携带运行时状态(pid / state) — 运行时由 `Tunnel` 单独维护。
/// 这是关键不变量:改 Profile 不影响已运行的 Tunnel,反之亦然。
public struct Profile: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID

    public var name: String
    public var sshHostAlias: String

    public var forwards: [PortForward]
    public var behavior: Behavior

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        sshHostAlias: String,
        forwards: [PortForward],
        behavior: Behavior,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sshHostAlias = sshHostAlias
        self.forwards = forwards
        self.behavior = behavior
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public struct Behavior: Codable, Hashable, Sendable {
        public var enabled: Bool
        public var autoReconnect: Bool
        public var autoStart: Bool

        public init(enabled: Bool, autoReconnect: Bool, autoStart: Bool) {
            self.enabled = enabled
            self.autoReconnect = autoReconnect
            self.autoStart = autoStart
        }

        public static let defaults = Behavior(
            enabled: true, autoReconnect: true, autoStart: false
        )
    }
}

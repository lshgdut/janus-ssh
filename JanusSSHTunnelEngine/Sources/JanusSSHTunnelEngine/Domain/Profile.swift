import Foundation

/// Profile 是 Janus 用户创建的"一组 SSH Tunnel 配置"。
///
/// 一个 Profile = 一个 SSH Process = N 个 Port Forward。
///
/// Profile 故意不携带运行时状态(pid / state) — 运行时由 `Tunnel` 单独维护。
/// 这是关键不变量:改 Profile 不影响已运行的 Tunnel,反之亦然。
struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID

    var name: String
    var sshHostAlias: String

    var forwards: [PortForward]
    var behavior: Behavior

    var createdAt: Date
    var updatedAt: Date

    init(
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

    struct Behavior: Codable, Hashable, Sendable {
        var enabled: Bool
        var autoReconnect: Bool
        var autoStart: Bool

        static let defaults = Behavior(
            enabled: true, autoReconnect: true, autoStart: false
        )
    }
}
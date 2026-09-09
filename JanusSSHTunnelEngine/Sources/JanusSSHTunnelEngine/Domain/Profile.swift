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

// MARK: - Duplication

extension Profile {
    /// 复制当前 profile —— 新 UUID、新时间戳、name 加 " Copy" 后缀。
    /// takenNames 用于避让: 如果 "Foo Copy" 已存在,自动改成 "Foo Copy 2"、"Foo Copy 3" ...
    ///
    /// 纯函数 — 调用方负责 register 到 TunnelManager + 通过 profileRepo 持久化。
    /// forwards 是 value-type 数组,直接赋就完成独立复制,无需显式深拷贝。
    public func duplicated(takenNames: Set<String>) -> Profile {
        let baseName = "\(name) Copy"
        let newName = Profile.uniqueCopyName(base: baseName, taken: takenNames)
        let now = Date()
        return Profile(
            id: UUID(),
            name: newName,
            sshHostAlias: sshHostAlias,
            forwards: forwards,
            behavior: behavior,
            createdAt: now,
            updatedAt: now
        )
    }

    /// 找最小可用名字 — 不补洞,直接递增找最小未占用的数字。
    /// 行为对齐 macOS Finder 的 "report (2).txt" 命名约定。
    private static func uniqueCopyName(base: String, taken: Set<String>) -> String {
        guard !taken.contains(base) else {
            var n = 2
            while taken.contains("\(base) \(n)") { n += 1 }
            return "\(base) \(n)"
        }
        return base
    }
}

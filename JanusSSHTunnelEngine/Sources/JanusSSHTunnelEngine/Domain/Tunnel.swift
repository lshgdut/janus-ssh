import Foundation

/// 运行时 Tunnel — 与 Profile 严格解耦。
///
/// Tunnel 持有 `profileSnapshot`(启动时的不可变副本),保证运行时不受 Profile 修改影响。
public struct Tunnel: Identifiable, Sendable {
    public let id: UUID

    public var profileSnapshot: ProfileSnapshot
    public var state: TunnelState
    public var pid: Int32?
    public var startedAt: Date?
    public var stoppedAt: Date?
    public var lastError: TunnelError?

    public init(
        profileSnapshot: ProfileSnapshot,
        state: TunnelState = .stopped,
        pid: Int32? = nil,
        startedAt: Date? = nil,
        stoppedAt: Date? = nil,
        lastError: TunnelError? = nil
    ) {
        self.id = profileSnapshot.id
        self.profileSnapshot = profileSnapshot
        self.state = state
        self.pid = pid
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.lastError = lastError
    }
}

/// Profile 的不可变运行时快照。
/// Tunnel 启动时拍下此快照,之后改 Profile 不影响正在运行的 SSH 进程。
public struct ProfileSnapshot: Sendable {
    let id: UUID
    let name: String
    let sshHostAlias: String
    let forwards: [PortForward]
    let autoReconnect: Bool
    let autoStart: Bool
    let enabled: Bool

    public init(_ profile: Profile) {
        self.id = profile.id
        self.name = profile.name
        self.sshHostAlias = profile.sshHostAlias
        self.forwards = profile.forwards
        self.autoReconnect = profile.behavior.autoReconnect
        self.autoStart = profile.behavior.autoStart
        self.enabled = profile.behavior.enabled
    }

    public init(
        id: UUID,
        name: String,
        sshHostAlias: String,
        forwards: [PortForward],
        autoReconnect: Bool
    ) {
        self.id = id
        self.name = name
        self.sshHostAlias = sshHostAlias
        self.forwards = forwards
        self.autoReconnect = autoReconnect
        self.autoStart = false
        self.enabled = true
    }
}
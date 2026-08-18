import Foundation

/// 运行时 Tunnel — 与 Profile 严格解耦。
///
/// Tunnel 持有 `profileSnapshot`(启动时的不可变副本),保证运行时不受 Profile 修改影响。
struct Tunnel: Identifiable, Sendable {
    let id: UUID

    var profileSnapshot: ProfileSnapshot
    var state: TunnelState
    var pid: Int32?
    var startedAt: Date?
    var stoppedAt: Date?
    var lastError: TunnelError?

    init(
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
struct ProfileSnapshot: Sendable {
    let id: UUID
    let name: String
    let sshHostAlias: String
    let forwards: [PortForward]
    let autoReconnect: Bool
    let autoStart: Bool
    let enabled: Bool

    init(_ profile: Profile) {
        self.id = profile.id
        self.name = profile.name
        self.sshHostAlias = profile.sshHostAlias
        self.forwards = profile.forwards
        self.autoReconnect = profile.behavior.autoReconnect
        self.autoStart = profile.behavior.autoStart
        self.enabled = profile.behavior.enabled
    }

    init(
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
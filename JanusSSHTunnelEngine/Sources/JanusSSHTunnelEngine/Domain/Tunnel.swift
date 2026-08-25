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

    // MARK: - State transitions
    //
    // 集中所有写状态机的辅助方法 — 之前 `TunnelManager.stop(...)`,
    // `TunnelManager.stopAll(...)`,`TunnelManager.stopAllNow()` 都各自 inline
    // 一份 `state = .stopping` / `state = .stopped` + 配套 `pid = nil` 等清零,
    // 5 行块在三处复制。code-review 顶级 finding(#10)指出这种重复容易"加 pauseAll()
    // 时第三处出现,跟现有两处漂移"。
    // 抽出后:
    //   - 唯一一处约定:"stopped 意味着 pid 清空、lastError 清零、stoppedAt = now"
    //   - 加 `pause()` / `error()` / `retrying()` 等新路径只需在 Tunnel 自己加,
    //     TunnelManager 不重复。
    //
    // 用 `mutating` 是因为这是 value-type,mutating 函数在 inout 时原地改,
    // 调用处仍要 `var t = tunnels[id]; t.markStopped(); tunnels[id] = t` 写回 dict。

    /// 进入"正在停"的过渡态。仅过渡,期待 observer 后续命中 .terminated
    /// 或者 TunnelManager 自己收尾。
    public mutating func markStopping() {
        state = .stopping
    }

    /// 收尾到 .stopped — 清 pid、lastError,记 stoppedAt = now。
    /// 用于 TunnelManager.stop(profileID:)、TunnelManager.stopAll() 两种
    /// 停止路径的"进程已死"收尾。
    public mutating func markStopped(now: Date = Date()) {
        state = .stopped
        stoppedAt = now
        pid = nil
        lastError = nil
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
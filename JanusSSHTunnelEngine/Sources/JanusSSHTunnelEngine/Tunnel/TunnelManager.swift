import Foundation

/// TunnelManager — 整个 App 的核心 orchestrator。
///
/// 责任:
/// 1. 维护 profile → Tunnel 映射
/// 2. 状态机转换
/// 3. 跨 profile 端口冲突检测
/// 4. Start All / Stop All
/// 5. 转发 SSH 事件到 LogStore
///
/// 注意:TunnelManager 自身是 `@MainActor`(UI 直接观察),
/// 内部通过 Task 把重活转给后台。
@MainActor
@Observable
public final class TunnelManager {

    /// UI 直接观察
    public private(set) var tunnels: [UUID: Tunnel] = [:]

    private let processManager: SSHProcessManaging
    private let portChecker: PortChecking
    private let validator: ProfileValidator
    private let logStore: TunnelLogStore
    private let reconnectController: ReconnectController
    private let sshConfigProvider: SSHConfigProviding?
    /// 可选 — 用于 App 重启后 sweep 孤儿 SSH 进程
    private let pidStore: ManagedPIDStore?

    /// profile 注册表 — 启动前要知道有哪些 profile
    private var profiles: [UUID: Profile] = [:]

    /// 跟踪每个 profile 的事件观察 Task — unregister 时需要 cancel 避免泄漏
    private var observationTasks: [UUID: Task<Void, Never>] = [:]

    /// 用户主动 stop 的 profile 集合 — 用来防止观察任务的
    /// `handleProcessExit` 把 user-requested termination(SIGTERM/SIGKILL,
    /// 退出码非 0)误判为 .error。用户 stop 后由 stop() 自己负责置 .stopped。
    private var userRequestedStop: Set<UUID> = []

    public init(
        processManager: SSHProcessManaging,
        portChecker: PortChecking,
        validator: ProfileValidator,
        logStore: TunnelLogStore,
        reconnectController: ReconnectController = ReconnectController(),
        sshConfigProvider: SSHConfigProviding? = nil,
        pidStore: ManagedPIDStore? = nil
    ) {
        self.processManager = processManager
        self.portChecker = portChecker
        self.validator = validator
        self.logStore = logStore
        self.reconnectController = reconnectController
        self.sshConfigProvider = sshConfigProvider
        self.pidStore = pidStore
    }

    // MARK: - Profile registry

    public func registerProfile(_ profile: Profile) {
        profiles[profile.id] = profile
        if tunnels[profile.id] == nil {
            tunnels[profile.id] = Tunnel(
                profileSnapshot: ProfileSnapshot(profile),
                state: .stopped
            )
        }
    }

    public func unregisterProfile(id: UUID) {
        profiles.removeValue(forKey: id)
        tunnels.removeValue(forKey: id)
        // 取消正在进行的重连 + 事件观察任务
        // reconnectController 是 actor — fire-and-forget
        Task { await reconnectController.cancel(profileID: id) }
        observationTasks[id]?.cancel()
        observationTasks.removeValue(forKey: id)
    }

    public func tunnel(for profileID: UUID) -> Tunnel? {
        tunnels[profileID]
    }

    // MARK: - Commands

    public func start(profileID: UUID) async throws {
        guard let profile = profiles[profileID] else {
            throw TunnelError.profileNotFound(profileID)
        }

        // 不启动 disabled 的 profile
        guard profile.behavior.enabled else {
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Profile is disabled, skipping start.",
                                  level: .warn)
            return
        }

        // 校验 — 用 sshConfigProvider 拿真实 knownHosts
        // 之前传 knownHosts: [] 会导致 sshHostAlias 检查永远失败
        let knownHosts = await currentKnownHosts()
        let issues = validator.validate(profile, knownHosts: knownHosts)
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            // 之前无脑写 .sshConfigResolutionFailed — 用户看到"ssh config invalid"
            // 实际却是端口重复 / 端口越界 / 名字空等,排查方向全错。
            // 现在按 field 把首条错误映射到具体 TunnelError,UI 才能给 actionable 文案。
            let first = errors.first
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Validation failed: \(first?.message ?? "unknown")",
                                  level: .error)
            updateTunnel(id: profileID) { t in
                t.state = .error
                t.lastError = Self.classify(validationIssue: first, profile: profile)
            }
            return
        }

        // Port 检查
        var unavailable: UInt16?
        for forward in profile.forwards {
            let available = await portChecker.isPortAvailable(host: forward.localHost, port: forward.localPort)
            if !available {
                unavailable = forward.localPort
                break
            }
        }
        if let port = unavailable {
            updateTunnel(id: profileID) { t in
                t.state = .error
                t.lastError = .localPortUnavailable(port)
            }
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Local port \(port) is in use.",
                                  level: .error)
            return
        }

        // 构造命令 + 启动
        let snapshot = ProfileSnapshot(profile)
        let commandBuilder = SSHCommandBuilder()
        let cmd: SSHCommand
        do {
            cmd = try commandBuilder.build(profile: snapshot)
        } catch {
            updateTunnel(id: profileID) { t in
                t.state = .error
                t.lastError = .sshConfigResolutionFailed(host: profile.sshHostAlias)
            }
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Failed to build SSH command: \(error)",
                                  level: .error)
            return
        }

        // Tunnel 状态: starting
        updateTunnel(id: profileID) { t in
            t.state = .starting
            t.profileSnapshot = snapshot
            t.startedAt = Date()
            t.lastError = nil
        }
        await logStore.append(profileID: profileID, kind: .app,
                              message: "Starting tunnel for profile \"\(profile.name)\"")

        do {
            let handle = try await processManager.launch(profileID: profileID, command: cmd)
            let pid = await handle.pid()
            updateTunnel(id: profileID) { t in
                t.pid = pid
                t.state = .running
            }
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Tunnel started · PID \(pid.map(String.init) ?? "?")")

            // 记录 PID 到持久化存储,下次 App 启动时 sweep 孤儿进程
            if let pid = pid, let store = pidStore {
                await store.record(profileID: profileID, pid: pid)
            }

            // 启动事件观察任务,转发到 logStore
            observationTasks[profileID] = startObserving(profileID: profileID, handle: handle)
        } catch let spawnError as SSHProcessError {
            // SSH 进程 spawn 失败 — 把描述写到 lastError / log
            updateTunnel(id: profileID) { t in
                t.state = .error
                t.lastError = .sshSpawnFailed(code: -1)
            }
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Spawn failed: \(spawnError.errorDescription ?? "unknown")",
                                  level: .error)
        } catch {
            updateTunnel(id: profileID) { t in
                t.state = .error
                t.lastError = .sshSpawnFailed(code: -1)
            }
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Failed to spawn SSH: \(error)",
                                  level: .error)
        }
    }

    public func stop(profileID: UUID) async throws {
        guard profiles[profileID] != nil else {
            throw TunnelError.profileNotFound(profileID)
        }

        // 幂等:已经在 stop / stopped 状态就不重复触发
        let current = tunnels[profileID]?.state
        if current == .stopping || current == .stopped {
            return
        }

        // 标记 user-requested,阻止后续 .terminated 事件把状态错置为 .error
        userRequestedStop.insert(profileID)
        updateTunnel(id: profileID) { t in
            t.state = .stopping
        }
        await processManager.terminate(profileID: profileID, reason: .userRequested)

        // terminate() 已确保进程死亡(graceful SIGTERM 5s 内 / 否则 SIGKILL),
        // 直接置 .stopped — 不依赖观察任务的 .terminated 事件
        updateTunnel(id: profileID) { t in
            t.state = .stopped
            t.stoppedAt = Date()
            t.pid = nil
            t.lastError = nil
        }
        await logStore.append(profileID: profileID, kind: .app,
                              message: "User requested stop · tunnel stopped")
    }

    public func restart(profileID: UUID) async throws {
        guard profiles[profileID] != nil else {
            throw TunnelError.profileNotFound(profileID)
        }
        await processManager.terminate(profileID: profileID, reason: .userRequested)
        updateTunnel(id: profileID) { t in
            t.state = .stopping
        }
        await logStore.append(profileID: profileID, kind: .app,
                              message: "Restart requested")
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms 缓冲
        try await start(profileID: profileID)
    }

    public func startAll() async throws {
        for profile in profiles.values where profile.behavior.enabled {
            try? await start(profileID: profile.id)
        }
    }

    public func stopAll() async {
        await processManager.terminateAll(reason: .userRequested)
        for id in tunnels.keys {
            updateTunnel(id: id) { $0.state = .stopping }
        }
    }

    /// App willTerminate 用的同步路径 — 不 await,fire-and-forget。
    /// 即使 App 立刻退出也能保证 SIGKILL 已下发。
    public func stopAllNow() {
        processManager.terminateAllNow()
        for id in tunnels.keys {
            updateTunnel(id: id) { $0.state = .stopping }
        }
    }

    // MARK: - Private

    /// 把 ProfileValidator 的首条错误映射到对应的 TunnelError。
    /// 之前无脑 .sshConfigResolutionFailed,UI 文案"ssh config invalid"对端口重复
    /// / 名字空等场景是误导。这里按 `field` 分类:host → hostUnknown、
    /// 端口重复 → duplicateLocalPort,其余退回 .sshConfigResolutionFailed。
    static func classify(validationIssue: ValidationIssue?, profile: Profile) -> TunnelError {
        guard let issue = validationIssue, let field = issue.field else {
            return .sshConfigResolutionFailed(host: profile.sshHostAlias)
        }
        if field == "sshHostAlias" {
            return .hostUnknown(profile.sshHostAlias)
        }
        if field.hasSuffix(".localPort") {
            // 解析 "forwards[3].localPort" → 取尾段数字
            // 优先报端口范围问题(永远 duplicates 也算) — 实际上消息里有 "duplicated" 关键字
            if issue.message.contains("duplicated") || issue.message.contains("duplicate") {
                return .duplicateLocalPort(profile.forwards.first?.localPort ?? 0)
            }
            // 端口越界 / 0 — 也归 duplicateLocalPort 用 0 占位
            return .duplicateLocalPort(profile.forwards.first?.localPort ?? 0)
        }
        // name / forwards(empty) / forwards[N].localHost / forwards[N].remoteHost
        // 没有精确对应,退回最接近的"配置问题"
        return .sshConfigResolutionFailed(host: profile.sshHostAlias)
    }

    /// 拉取当前 ~/.ssh/config 中的 host alias 集合。
    /// 没有 provider 时返回空集 — 此时编辑器校验已保证 alias 合法,
    /// 运行时不做 host 存在性检查(避免硬依赖)。
    private func currentKnownHosts() async -> Set<String> {
        guard let provider = sshConfigProvider else { return [] }
        let hosts = (try? await provider.discoverHosts()) ?? []
        return Set(hosts.map { $0.alias })
    }

    private func updateTunnel(id: UUID, _ mutation: (inout Tunnel) -> Void) {
        guard var t = tunnels[id] else { return }
        mutation(&t)
        tunnels[id] = t
    }

    private func startObserving(profileID: UUID, handle: SSHProcessHandle) -> Task<Void, Never> {
        // 返回 Task 句柄,让 unregisterProfile 能 cancel
        return Task { [logStore] in
            let stream = await handle.events()
            for await event in stream {
                if Task.isCancelled { return }
                switch event {
                case .stdout(let data):
                    let text = String(data: data, encoding: .utf8) ?? ""
                    for line in text.split(separator: "\n") {
                        await logStore.append(profileID: profileID, kind: .stdout,
                                              message: String(line))
                    }
                case .stderr(let data):
                    let text = String(data: data, encoding: .utf8) ?? ""
                    for line in text.split(separator: "\n") {
                        await logStore.append(profileID: profileID, kind: .stderr,
                                              message: String(line), level: .warn)
                    }
                case .terminated(let code, let reason):
                    await self.handleProcessExit(
                        profileID: profileID, code: code, reason: reason)
                    return
                }
            }
        }
    }

    private func handleProcessExit(
        profileID: UUID,
        code: Int32,
        reason: SSHProcess.ProcessEndedReason
    ) async {
        // 任何退出路径(用户主动 / 进程自然死)都从持久化 PID 列表里清掉,
        // 否则 App 重启时 sweep 会误杀还在运行的合法 SSH。
        if let store = pidStore {
            await store.remove(profileID: profileID)
        }

        // 用户主动 stop 时,stop() 已经把状态置 .stopped;
        // 这里的 .terminated 是 terminate() 之后的副作用,忽略。
        if userRequestedStop.remove(profileID) != nil {
            return
        }

        let success = (code == 0)
        updateTunnel(id: profileID) { t in
            t.state = success ? .stopped : .error
            t.stoppedAt = Date()
            t.pid = nil
            if !success {
                t.lastError = .sshExited(code: code, signal: nil, reason: .processExited)
            } else {
                t.lastError = nil
            }
        }
        await logStore.append(profileID: profileID, kind: .app,
                              message: "SSH exited with code \(code) (\(reason))",
                              level: success ? .info : .error)

        // Auto Reconnect:仅当 (1) 异常退出 (2) Profile 配置了 autoReconnect
        if !success && reason == .exited {
            let profile = profiles[profileID]
            if profile?.behavior.autoReconnect == true {
                updateTunnel(id: profileID) { $0.state = .reconnecting }
                await logStore.append(profileID: profileID, kind: .app,
                                      message: "Auto-reconnect scheduled",
                                      level: .info)
                // ReconnectController 是 actor,需要 await 跨 actor 边界
                let controller = reconnectController
                let weakSelf = WeakSelf(self)
                let pid = profileID
                Task {
                    await controller.schedule(profileID: pid) {
                        // start() throws — ReconnectController 不需要返回值,
                        // 失败由 TunnelManager 内部已设置 error 状态
                        try? await weakSelf.value?.start(profileID: pid)
                    }
                }
            }
        }
    }
}
/// Sendable 弱引用包装 — 用于跨 actor 传递 self 避免 strong capture
public final class WeakSelf<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    public init(_ value: T) { self.value = value }
}

#if DEBUG
public extension TunnelManager {
    /// 仅供 SwiftUI Preview / Live Preview 注入 mock state。
    /// 不能用于生产代码 — 直接绕过状态机。
    @MainActor
    func _previewSetState(profileID: UUID,
                          state: TunnelState,
                          startedAt: Date? = nil,
                          stoppedAt: Date? = nil,
                          lastError: TunnelError? = nil) {
        guard tunnels[profileID] != nil else { return }
        updateTunnel(id: profileID) { t in
            t.state = state
            t.startedAt = startedAt
            t.stoppedAt = stoppedAt
            t.lastError = lastError
        }
    }
}
#endif

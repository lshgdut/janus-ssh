import Foundation

/// TunnelService — App 核心 orchestrator(从原 `TunnelManager` 拆分而来)。
///
/// 责任:
/// 1. 维护 profile → Tunnel 映射 (`tunnels: [UUID: Tunnel]`)
/// 2. 状态机转换(starting / running / stopping / stopped / reconnecting / error)
/// 3. 跨 profile 端口冲突检测
/// 4. Start All / Stop All
/// 5. 转发 SSH 事件到 LogStore
///
/// 与 `TunnelManager` 的关系:
/// - TunnelManager 在 Task 7 删除。Task 4 的范围是把"orchestrator 部分"搬到
///   TunnelService,但**不**改 TunnelManager 的对外 API(那是 Task 7 的 shim 工作)。
/// - App 这一层在 Task 7 之后才会切到 TunnelService。
///
/// 与 `ReconnectService` / `ManagedPIDService` 的关系:
/// - 这两个服务在 Task 4 的上一轮迭代已经存在。
/// - TunnelService 把它们作为依赖注入,通过 protocol 而不是具体类引用。
///
/// 关键不变式(从 TunnelManager 平移过来,与 commit d2c61cd / 36a2975 / 2306d1a
/// 对齐):
/// - `userRequestedStop: Set<UUID>` 防御 — `stop()` / `stopAll()` 入口插入,
///   observation task 的 `handleProcessExit` 命中后 early-return。
/// - `generations[id]: Int` 计数器 — `start()` 入口 +1;observation task 把当前值
///   拍进闭包,`handleProcessExit` 收到 .terminated 时如果 generation 对不上
///   当前值就丢弃(防止 restart / 老进程死亡事件被误用)。
/// - `Tunnel.markStopping()` / `markStopped(now:)` 单一约定(见 Tunnel.swift)。
/// - `stopAll()` 不覆盖 .error / .stopped 隧道的诊断信息。
///
/// 错误类型:目前仍然抛 `TunnelError`(11 个 case) — 与既有 `TunnelManager`
/// 行为一致。Task 7 把 tunnel-specific 的 case(`.duplicateLocalPort`、
/// `.localPortUnavailable`)合并到 `AppError` 时,本文件需要相应迁移。
@MainActor
@Observable
public final class TunnelService {

    /// UI 直接观察的 tunnels 字典。
    public private(set) var tunnels: [UUID: Tunnel] = [:]

    // MARK: - Dependencies

    private let processManager: SSHProcessManaging
    private let portChecker: PortChecking
    private let validator: ProfileValidator
    private let logStore: TunnelLogStore
    private let reconnectService: ReconnectService
    private let managedPIDService: ManagedPIDService
    private let sshConfigProvider: SSHConfigProviding?
    private let profileProvider: @Sendable () async -> [Profile]

    // MARK: - Internal state

    private var observationTasks: [UUID: Task<Void, Never>] = [:]
    private var userRequestedStop: Set<UUID> = []
    private var generations: [UUID: Int] = [:]

    public init(
        processManager: SSHProcessManaging,
        portChecker: PortChecking,
        validator: ProfileValidator,
        logStore: TunnelLogStore,
        reconnectService: ReconnectService,
        managedPIDService: ManagedPIDService,
        sshConfigProvider: SSHConfigProviding? = nil,
        profileProvider: @escaping @Sendable () async -> [Profile]
    ) {
        self.processManager = processManager
        self.portChecker = portChecker
        self.validator = validator
        self.logStore = logStore
        self.reconnectService = reconnectService
        self.managedPIDService = managedPIDService
        self.sshConfigProvider = sshConfigProvider
        self.profileProvider = profileProvider
    }

    // MARK: - Profile registry

    /// 注册 profile 到 TunnelService。tunnel 字典里没条目时插一条 `.stopped` 占位。
    /// 与既有 `TunnelManager.registerProfile` 行为对齐。
    public func registerProfile(_ profile: Profile) {
        if tunnels[profile.id] == nil {
            tunnels[profile.id] = Tunnel(
                profileSnapshot: ProfileSnapshot(profile),
                state: .stopped
            )
        }
    }

    /// 注销 profile — 把可能仍在跑的 SSH 进程杀掉,取消 reconnect + 观察任务。
    public func unregisterProfile(id: UUID) {
        Task { await processManager.terminate(profileID: id, reason: .userRequested) }
        Task { await reconnectService.cancel(profileID: id) }
        observationTasks[id]?.cancel()
        observationTasks.removeValue(forKey: id)
        tunnels.removeValue(forKey: id)
    }

    public func tunnel(for profileID: UUID) -> Tunnel? {
        tunnels[profileID]
    }

    // MARK: - Commands

    public func start(profileID: UUID) async throws {
        let profiles = await profileProvider()
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            throw TunnelError.profileNotFound(profileID)
        }

        guard profile.behavior.enabled else {
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Profile is disabled, skipping start.",
                                  level: .warn)
            return
        }

        // Defense-in-depth:清掉上次 stop() 漏清的 userRequestedStop 残留。
        userRequestedStop.remove(profileID)
        await reconnectService.markUserStop(profileID: profileID, stopped: false)

        // 校验 — 用 sshConfigProvider 拿真实 knownHosts
        let knownHosts = await currentKnownHosts()
        let issues = validator.validate(profile, knownHosts: knownHosts)
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
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

        // 构造命令
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

        // Bump generation BEFORE launching the new process.
        let generation = (generations[profileID] ?? 0) + 1
        generations[profileID] = generation

        do {
            let handle = try await processManager.launch(profileID: profileID, command: cmd)
            let pid = await handle.pid()
            updateTunnel(id: profileID) { t in
                t.pid = pid
                t.state = .running
            }
            await logStore.append(profileID: profileID, kind: .app,
                                  message: "Tunnel started · PID \(pid.map(String.init) ?? "?")")

            // 记录 PID 到 ManagedPIDService(App 重启时 sweep 用)
            if let pid = pid {
                try? await managedPIDService.track(pid: pid, exePath: "/usr/bin/ssh", profileID: profileID)
            }

            observationTasks[profileID] = startObserving(
                profileID: profileID, handle: handle, generation: generation)
        } catch let spawnError as SSHProcessError {
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
        let profiles = await profileProvider()
        guard profiles.first(where: { $0.id == profileID }) != nil else {
            throw TunnelError.profileNotFound(profileID)
        }

        // 幂等
        let current = tunnels[profileID]?.state
        if current == .stopping || current == .stopped {
            return
        }

        userRequestedStop.insert(profileID)
        await reconnectService.markUserStop(profileID: profileID, stopped: true)
        updateTunnel(id: profileID) { t in
            t.markStopping()
        }
        await processManager.terminate(profileID: profileID, reason: .userRequested)

        updateTunnel(id: profileID) { t in
            t.markStopped()
        }
        await reconnectService.cancel(profileID: profileID)
        await logStore.append(profileID: profileID, kind: .app,
                              message: "User requested stop · tunnel stopped")
    }

    public func restart(profileID: UUID) async throws {
        let profiles = await profileProvider()
        guard profiles.first(where: { $0.id == profileID }) != nil else {
            throw TunnelError.profileNotFound(profileID)
        }
        // 1) cancel 老 observation task
        observationTasks[profileID]?.cancel()
        observationTasks.removeValue(forKey: profileID)
        // 2) 设 userRequestedStop 作为 cancel 还没生效的窗口期兜底
        userRequestedStop.insert(profileID)
        await reconnectService.markUserStop(profileID: profileID, stopped: true)
        await processManager.terminate(profileID: profileID, reason: .userRequested)
        updateTunnel(id: profileID) { t in
            t.state = .stopping
        }
        await logStore.append(profileID: profileID, kind: .app,
                              message: "Restart requested")
        try await Task.sleep(nanoseconds: 200_000_000)
        try await start(profileID: profileID)
    }

    public func startAll() async throws {
        let profiles = await profileProvider()
        for profile in profiles where profile.behavior.enabled {
            try? await start(profileID: profile.id)
        }
    }

    public func stopAll() async {
        // 范围比 per-profile stop() 宽:覆盖所有活跃态,保留诊断态。
        for id in tunnels.keys {
            userRequestedStop.insert(id)
        }
        // 取消所有 profile 的 reconnect schedule
        let ids = Array(tunnels.keys)
        for id in ids {
            await reconnectService.markUserStop(profileID: id, stopped: true)
            await reconnectService.cancel(profileID: id)
        }

        await processManager.terminateAll(reason: .userRequested)

        for id in tunnels.keys {
            updateTunnel(id: id) { t in
                switch t.state {
                case .running, .starting, .reconnecting, .stopping:
                    t.markStopped()
                case .stopped, .error:
                    break  // 保留诊断信息
                }
            }
        }
    }

    /// App willTerminate 同步路径 — 不 await,fire-and-forget。
    public func stopAllNow() {
        processManager.terminateAllNow()
        for id in tunnels.keys {
            updateTunnel(id: id) { $0.state = .stopping }
        }
    }

    // MARK: - Private

    /// 把 ProfileValidator 的首条错误映射到对应的 TunnelError(沿用 TunnelManager.classify)。
    static func classify(validationIssue: ValidationIssue?, profile: Profile) -> TunnelError {
        guard let issue = validationIssue, let field = issue.field else {
            return .sshConfigResolutionFailed(host: profile.sshHostAlias)
        }
        if field == "sshHostAlias" {
            return .hostUnknown(profile.sshHostAlias)
        }
        if field.hasSuffix(".localPort") {
            if issue.message.contains("duplicated") || issue.message.contains("duplicate") {
                return .duplicateLocalPort(profile.forwards.first?.localPort ?? 0)
            }
            return .duplicateLocalPort(profile.forwards.first?.localPort ?? 0)
        }
        return .sshConfigResolutionFailed(host: profile.sshHostAlias)
    }

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

    private func startObserving(
        profileID: UUID,
        handle: SSHProcessHandle,
        generation: Int
    ) -> Task<Void, Never> {
        Task { [logStore] in
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
                        profileID: profileID,
                        code: code,
                        reason: reason,
                        generation: generation)
                    return
                }
            }
        }
    }

    private func handleProcessExit(
        profileID: UUID,
        code: Int32,
        reason: SSHProcess.ProcessEndedReason,
        generation: Int
    ) async {
        // 丢弃老进程留下的过期 .terminated 事件
        guard generations[profileID] == generation else { return }

        // 任何退出路径都从持久化 PID 列表里清掉
        if let pid = tunnels[profileID]?.pid {
            try? await managedPIDService.clear(pid: pid)
        }

        // 用户主动 stop → stop() 已收尾,忽略迟到的 .terminated
        if userRequestedStop.remove(profileID) != nil {
            return
        }

        let success = (code == 0)
        let alreadyFinalized = (tunnels[profileID]?.state == .stopped)
        if !alreadyFinalized {
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
        }

        // Auto Reconnect — 委托 ReconnectService 决策
        if !success && reason == .exited {
            let current = tunnels[profileID]?.state
            if current != .running && current != .starting && current != .reconnecting {
                return
            }
            let profiles = await profileProvider()
            let profile = profiles.first(where: { $0.id == profileID })
            if profile?.behavior.autoReconnect == true {
                updateTunnel(id: profileID) { $0.state = .reconnecting }
                await logStore.append(profileID: profileID, kind: .app,
                                      message: "Auto-reconnect scheduled",
                                      level: .info)
                let decision = await reconnectService.onProcessExited(profileID: profileID)
                switch decision {
                case .reconnect(let delay):
                    let pid = profileID
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        try? await self?.start(profileID: pid)
                    }
                case .skip:
                    break
                }
            }
        }
    }
}

#if DEBUG
public extension TunnelService {
    /// 仅供 SwiftUI Preview / Live Preview 注入 mock state。
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

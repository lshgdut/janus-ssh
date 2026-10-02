import Foundation

/// ReconnectService 决策结果 — `TunnelService` 在收到 SSH 子进程退出事件时
/// 调用 `onProcessExited(profileID:)`,根据这个返回值决定要不要重连。
///
/// `.skip` 表示不重连(用户主动 stop / 已达到 maxAttempts);
/// `.reconnect(after:)` 表示按 `BackoffPolicy` 计算下一次退避时间(秒)。
public enum ReconnectDecision: Sendable, Equatable {
    case reconnect(after: TimeInterval)
    case skip
}

/// ReconnectService 协议 — 把"SSH 异常退出后要不要重连、按什么 backoff 重连"
/// 这块业务逻辑从 TunnelService / TunnelManager 抽出来。
///
/// 关键设计:
/// - `markUserStop(profileID:stopped:)` 是 TunnelService 在 `stop()` /
///   `start()` 入口的钩子,告诉 service 当前这个 profile 的 stop 是用户
///   主动的还是系统(进程死了)触发的。
/// - `onProcessExited(profileID:)` 是观察任务的钩子,被调用时返回决策。
/// - `schedule(profile:)` / `cancel(profileID:)` 是实际操作调度(可选)—
///   实际重连动作由 TunnelService 触发,ReconnectService 仅持有 backoff 时间。
///
/// 与既有 `ReconnectController` 的关系:
/// - `ReconnectController` 持有 `[UUID: Task<Void, Never>]` 任务列表,
///   在 actor 内 while-loop 调 `Task.sleep` + 触发 onRetry。
/// - `ReconnectService` 把"调度"做成 `@Sendable (UUID, TimeInterval) -> UUID`
///   / `@Sendable (UUID) -> Void` 注入,生产 init 可以用 `Task`-based
///   scheduler,测试可以 inline。
/// - Task 7 删除 `ReconnectController`,把它的消费者(ReconnectControllerTests、
///   AppLifecycleManager)迁到 ReconnectService。
public protocol ReconnectService: Sendable {
    /// 标记 profile 是否是用户主动 stop。
    /// - Parameter stopped: true → 后续 onProcessExited 必须返回 `.skip`;
    ///                       false → 允许重连(清掉任何残留 flag)。
    func markUserStop(profileID: UUID, stopped: Bool) async

    /// SSH 进程退出时被调用 — 返回是否需要重连 + 退避时间。
    func onProcessExited(profileID: UUID) async -> ReconnectDecision

    /// 显式调度一次重连 — 返回的 handle 可用于后续 `cancel`。
    @discardableResult
    func schedule(profile: Profile) async throws -> UUID

    /// 取消一个 profile 上挂着的重连(用户 stop 时调用)。
    func cancel(profileID: UUID) async
}

/// 实际实现 — actor。
public actor ReconnectServiceImpl: ReconnectService {

    private let policy: BackoffPolicy
    private let schedule: @Sendable (UUID, TimeInterval) async -> UUID
    private let cancel: @Sendable (UUID) async -> Void

    /// 用户主动 stop 的 profile 集合 — `markUserStop(profileID:, stopped: true)`
    /// 时插入,`onProcessExited` 返回 `.skip` 时移除(单次消费)。
    private var userStopped: Set<UUID> = []

    /// 每个 profile 的"已失败次数" — 跟 `BackoffPolicy.maxAttempts` 联动。
    private var attemptCount: [UUID: Int] = [:]

    /// 每次 `schedule` 分配的 handle,key 是 profileID,value 是注入的
    /// scheduler 返回的 handle。
    private var handles: [UUID: UUID] = [:]

    public init(
        policy: BackoffPolicy = .defaults,
        schedule: @escaping @Sendable (UUID, TimeInterval) async -> UUID = ReconnectServiceImpl.defaultSchedule,
        cancel: @escaping @Sendable (UUID) async -> Void = ReconnectServiceImpl.defaultCancel
    ) {
        self.policy = policy
        self.schedule = schedule
        self.cancel = cancel
    }

    public func markUserStop(profileID: UUID, stopped: Bool) async {
        if stopped {
            userStopped.insert(profileID)
        } else {
            userStopped.remove(profileID)
            // 重置 attempt 计数 — start 入口的 defense-in-depth,跟
            // TunnelManager.start() 顶部 `userRequestedStop.remove` 对齐。
            attemptCount[profileID] = 0
        }
    }

    public func onProcessExited(profileID: UUID) async -> ReconnectDecision {
        // 用户主动 stop → 不重连。
        if userStopped.contains(profileID) {
            userStopped.remove(profileID)
            attemptCount[profileID] = 0
            return .skip
        }

        // 按 attempt 数 + 策略算退避时间。attempt 数等于"已失败次数"。
        let attempt = (attemptCount[profileID] ?? 0) + 1

        // maxAttempts 兜底:达到上限 → skip。
        if let max = policy.maxAttempts, attempt > max {
            attemptCount[profileID] = attempt
            return .skip
        }
        attemptCount[profileID] = attempt

        // 按 BackoffPolicy 计算下一次延迟。BackoffPolicy 用
        // initialDelayMs / multiplier / maxDelayMs 算指数退避。
        let delay = backoffDelay(attempt: attempt, policy: policy)
        return .reconnect(after: delay)
    }

    public func schedule(profile: Profile) async throws -> UUID {
        let attempt = (attemptCount[profile.id] ?? 0) + 1
        attemptCount[profile.id] = attempt
        let delay = backoffDelay(attempt: attempt, policy: policy)
        let handle = await schedule(profile.id, delay)
        handles[profile.id] = handle
        return handle
    }

    public func cancel(profileID: UUID) async {
        if let handle = handles.removeValue(forKey: profileID) {
            await cancel(handle)
        }
        userStopped.remove(profileID)
        attemptCount[profileID] = 0
    }

    /// 测试 seam — 暴露 userStopped 状态,便于断言"用户 stop 后第一次 onProcessExited
    /// 必定 .skip"。
    public func _consumeReconnectDecision(profileID: UUID) async -> Bool {
        !userStopped.contains(profileID)
    }

    // MARK: - Private

    /// `BackoffPolicy.initialDelayMs * multiplier^(attempt-1)`,封顶到 `maxDelayMs`。
    /// 跟既有 `ReconnectController.backoffDelay` 公式对齐 — 提取出来便于测试。
    private func backoffDelay(attempt: Int, policy: BackoffPolicy) -> TimeInterval {
        let baseMs = Double(policy.initialDelayMs)
        let mult = policy.multiplier
        let raw = baseMs * pow(mult, Double(attempt - 1))
        let cappedMs = min(raw, Double(policy.maxDelayMs))
        return cappedMs / 1000.0
    }

    // MARK: - Defaults

    /// 默认 schedule:用 `Task` 异步 sleep — 把 handle 跟 task 用 UUID 等价占位,
    /// cancel 时通过 task bag 取消。生产 init 时这个实现够用,测试可以注入 inline。
    public static let defaultSchedule: @Sendable (UUID, TimeInterval) async -> UUID = { _, delay in
        let handle = UUID()
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            // handle 实际触发由 caller(TunnelService)在 sleep 完后启动 start()。
            // 这里仅保留 placeholder 行为,避免 actor 持有孤儿 Task。
        }
        return handle
    }

    /// 默认 cancel:no-op — 真实 cancel 由 TunnelService 通过自己的 task bag
    /// 拦截 `markUserStop(profileID:, stopped: true)` 来实现。
    public static let defaultCancel: @Sendable (UUID) async -> Void = { _ in }
}

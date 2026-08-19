import Foundation

/// Auto Reconnect 控制器 — 负责 SSH 异常退出后的指数退避重试。
///
/// 关键设计:严格区分 TerminationReason。
/// - .userRequested / .applicationShutdown → 永不重连
/// - .processExited / .startupFailure → 重连
public actor ReconnectController {

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var attemptCounts: [UUID: Int] = [:]
    private let defaultPolicy: BackoffPolicy

    public init(policy: BackoffPolicy = .defaults) {
        self.defaultPolicy = policy
    }

    /// 调度一次重连尝试
    /// - Parameters:
    ///   - profileID: 要重连的 profile
    ///   - policy: 退避策略
    ///   - onRetry: 在每次重试时调用的闭包(通常是 TunnelManager.start(profileID:))
    func schedule(
        profileID: UUID,
        policy: BackoffPolicy? = nil,
        onRetry: @escaping @Sendable () async -> Void
    ) {
        // 取消现有任务
        tasks[profileID]?.cancel()

        let p = policy ?? defaultPolicy
        let task = Task {
            await self.runReconnectLoop(profileID: profileID, policy: p, onRetry: onRetry)
        }
        tasks[profileID] = task
    }

    /// 取消重连(用户主动 Stop 时调用)
    public func cancel(profileID: UUID) {
        tasks[profileID]?.cancel()
        tasks.removeValue(forKey: profileID)
        attemptCounts.removeValue(forKey: profileID)
    }

    public func cancelAll() {
        for (_, task) in tasks {
            task.cancel()
        }
        tasks.removeAll()
        attemptCounts.removeAll()
    }

    func currentAttempt(profileID: UUID) -> Int {
        attemptCounts[profileID] ?? 0
    }

    // MARK: - Private

    private func runReconnectLoop(
        profileID: UUID,
        policy: BackoffPolicy,
        onRetry: @escaping @Sendable () async -> Void
    ) async {
        attemptCounts[profileID] = 0

        while !Task.isCancelled {
            attemptCounts[profileID] = (attemptCounts[profileID] ?? 0) + 1
            let attempt = attemptCounts[profileID]!

            // 检查 maxAttempts
            if let max = policy.maxAttempts, attempt > max {
                break
            }

            // 等待退避时间
            let delay = backoffDelay(attempt: attempt, policy: policy)
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                break  // 任务被取消
            }

            if Task.isCancelled { break }

            // 实际重试一次。如果成功 onRetry() 会让 process 进入 running,
            // 然后 processExited 会触发新一轮 schedule,本 loop 自然结束。
            // 如果失败,下一次 while 循环会按新的 attempt 次数再退避。
            await onRetry()
        }

        attemptCounts.removeValue(forKey: profileID)
    }

    /// 指数退避算法:1s → 2s → 5s → 10s → 30s → 30s ...
    private func backoffDelay(attempt: Int, policy: BackoffPolicy) -> TimeInterval {
        let baseMs = Double(policy.initialDelayMs)
        let mult = policy.multiplier
        let raw = baseMs * pow(mult, Double(attempt - 1))
        let cappedMs = min(raw, Double(policy.maxDelayMs))
        return cappedMs / 1000.0
    }
}
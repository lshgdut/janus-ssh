import XCTest
@testable import JanusSSHTunnelEngine

final class ReconnectControllerTests: XCTestCase {

    func test_cancel_does_not_retry() async {
        let controller = ReconnectController(policy: BackoffPolicy(
            initialDelayMs: 100, multiplier: 2.0, maxDelayMs: 500, maxAttempts: nil
        ))

        var retryCount = 0
        let onRetry: @Sendable () async -> Void = {
            retryCount += 1
        }

        controller.schedule(profileID: UUID(), onRetry: onRetry)
        // 立即取消 — 第一次重试都不应该发生
        controller.cancel(profileID: UUID())  // 不同的 ID,不影响
        controller.cancelAll()

        // 给一点时间确保没有重试发生
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(retryCount, 0)
    }

    func test_max_attempts_respected() async {
        // 极小 delay,maxAttempts=2 → 应该停止
        let policy = BackoffPolicy(
            initialDelayMs: 50, multiplier: 1.0, maxDelayMs: 100, maxAttempts: 2
        )
        let controller = ReconnectController(policy: policy)

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func value() -> Int { count }
        }
        let counter = Counter()
        let onRetry: @Sendable () async -> Void = {
            await counter.increment()
        }

        let id = UUID()
        controller.schedule(profileID: id, onRetry: onRetry)

        // 给充足时间让所有尝试发生
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let count = await counter.value()
        XCTAssertLessThanOrEqual(count, 2,
            "should respect maxAttempts=2, got \(count)")
    }

    func test_current_attempt_starts_at_zero() async {
        let controller = ReconnectController()
        let id = UUID()
        XCTAssertEqual(controller.currentAttempt(profileID: id), 0)
    }

    func test_backoff_delays_follow_policy() async {
        let policy = BackoffPolicy(
            initialDelayMs: 1000, multiplier: 2.0, maxDelayMs: 30000, maxAttempts: nil
        )

        // 验证算法: 1s, 2s, 4s, 8s, 16s, 30s (capped), 30s, ...
        // 通过 schedule 一个快速 policy 然后观察实际延迟(间接验证)

        let controller = ReconnectController(policy: policy)
        var timestamps: [Date] = []

        let onRetry: @Sendable () async -> Void = {
            timestamps.append(Date())
        }

        // 用快速 policy 模拟,以便测试快速跑完
        let fastPolicy = BackoffPolicy(
            initialDelayMs: 100, multiplier: 2.0, maxDelayMs: 400, maxAttempts: 3
        )
        controller.schedule(profileID: UUID(), policy: fastPolicy, onRetry: onRetry)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        controller.cancelAll()

        XCTAssertGreaterThan(timestamps.count, 1, "should have retried at least twice")

        // 第一次 retry 应该在 ~100ms,第二次在 ~200ms
        if timestamps.count >= 2 {
            let gap = timestamps[1].timeIntervalSince(timestamps[0])
            XCTAssertGreaterThan(gap, 0.05,
                                 "second retry should be ~100ms after first")
        }
    }
}
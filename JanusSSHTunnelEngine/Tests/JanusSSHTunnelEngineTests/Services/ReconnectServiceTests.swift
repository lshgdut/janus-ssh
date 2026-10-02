import XCTest
@testable import JanusSSHTunnelEngine

final class ReconnectServiceTests: XCTestCase {

    func test_schedule_then_cancel_prevents_reconnect() async throws {
        let scheduledBag = PIDsBag()
        let cancelledBag = PIDsBag()
        let service = ReconnectServiceImpl(
            policy: BackoffPolicy(initialDelayMs: 1000, multiplier: 2.0, maxDelayMs: 30_000, maxAttempts: nil),
            schedule: { profileID, _ in
                await scheduledBag.add(profileID)
                return UUID()
            },
            cancel: { handle in await cancelledBag.add(handle) }
        )
        let profile = Profile(
            name: "p",
            sshHostAlias: "h",
            forwards: [],
            behavior: .defaults
        )

        let handle = try await service.schedule(profile: profile)
        await service.cancel(profileID: profile.id)

        let scheduled = await scheduledBag.snapshot()
        let cancelled = await cancelledBag.snapshot()
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first, profile.id)
        XCTAssertEqual(cancelled.count, 1)
        XCTAssertEqual(cancelled.first, handle)
    }

    func test_processExit_returns_reconnect_when_no_user_stop() async {
        let service = ReconnectServiceImpl(
            policy: BackoffPolicy(initialDelayMs: 1000, multiplier: 1.0, maxDelayMs: 1000, maxAttempts: nil),
            schedule: { _, _ in UUID() },
            cancel: { _ in }
        )
        let profile = Profile(
            name: "p",
            sshHostAlias: "h",
            forwards: [],
            behavior: .defaults
        )

        await service.markUserStop(profileID: profile.id, stopped: false)
        let decision = await service.onProcessExited(profileID: profile.id)

        // 1000ms initial / multiplier 1.0 → first attempt = 1s
        XCTAssertEqual(decision, .reconnect(after: 1.0))
    }

    func test_processExit_returns_skip_when_user_stopped() async {
        let service = ReconnectServiceImpl(
            policy: BackoffPolicy(initialDelayMs: 1000, multiplier: 1.0, maxDelayMs: 1000, maxAttempts: nil),
            schedule: { _, _ in UUID() },
            cancel: { _ in }
        )
        let profile = Profile(
            name: "p",
            sshHostAlias: "h",
            forwards: [],
            behavior: .defaults
        )

        await service.markUserStop(profileID: profile.id, stopped: true)
        let decision = await service.onProcessExited(profileID: profile.id)

        XCTAssertEqual(decision, .skip)
    }

    func test_processExit_respects_maxAttempts() async {
        let service = ReconnectServiceImpl(
            policy: BackoffPolicy(initialDelayMs: 100, multiplier: 1.0, maxDelayMs: 100, maxAttempts: 2),
            schedule: { _, _ in UUID() },
            cancel: { _ in }
        )
        let profileID = UUID()

        // 第一次 + 第二次失败 → reconnect
        let d1 = await service.onProcessExited(profileID: profileID)
        let d2 = await service.onProcessExited(profileID: profileID)
        // 第三次 → maxAttempts 触发 skip
        let d3 = await service.onProcessExited(profileID: profileID)

        XCTAssertEqual(d1, .reconnect(after: 0.1))
        XCTAssertEqual(d2, .reconnect(after: 0.1))
        XCTAssertEqual(d3, .skip)
    }

    func test_markUserStop_false_clears_user_stop_state() async {
        let service = ReconnectServiceImpl(
            policy: BackoffPolicy(initialDelayMs: 1000, multiplier: 1.0, maxDelayMs: 1000, maxAttempts: nil),
            schedule: { _, _ in UUID() },
            cancel: { _ in }
        )
        let profileID = UUID()

        await service.markUserStop(profileID: profileID, stopped: true)
        // 反转 — 跟 TunnelManager.start() 入口的 defense-in-depth 对齐
        await service.markUserStop(profileID: profileID, stopped: false)

        let decision = await service.onProcessExited(profileID: profileID)
        XCTAssertEqual(decision, .reconnect(after: 1.0))
    }

    func test_backoff_delay_follows_policy() async {
        // initialDelayMs=1000, multiplier=2.0, maxDelayMs=4000
        // → 1s, 2s, 4s, 4s(capped), 4s(capped) ...
        let service = ReconnectServiceImpl(
            policy: BackoffPolicy(initialDelayMs: 1000, multiplier: 2.0, maxDelayMs: 4000, maxAttempts: nil),
            schedule: { _, _ in UUID() },
            cancel: { _ in }
        )
        let profileID = UUID()

        // 累积 attempt → 每次 onProcessExited bump 1 次
        // 1st: 1000 * 2^0 = 1s
        let d1 = await service.onProcessExited(profileID: profileID)
        // 2nd: 1000 * 2^1 = 2s
        let d2 = await service.onProcessExited(profileID: profileID)
        // 3rd: 1000 * 2^2 = 4s (正好封顶)
        let d3 = await service.onProcessExited(profileID: profileID)
        // 4th: 1000 * 2^3 = 8s → 封顶到 4s
        let d4 = await service.onProcessExited(profileID: profileID)

        XCTAssertEqual(d1, .reconnect(after: 1.0))
        XCTAssertEqual(d2, .reconnect(after: 2.0))
        XCTAssertEqual(d3, .reconnect(after: 4.0))
        XCTAssertEqual(d4, .reconnect(after: 4.0))
    }
}

/// actor-based bag — 让 @Sendable closure 安全 mutate。
private actor PIDsBag {
    private var items: [UUID] = []
    func add(_ item: UUID) { items.append(item) }
    func snapshot() -> [UUID] { items }
}

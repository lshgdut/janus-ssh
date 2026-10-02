import XCTest
import os
@testable import JanusSSHTunnelEngine

/// TunnelService 是核心 Application Service。
/// 测试策略:用 FakeSSHProcessManager + FakeSSHProcessHandle 替换真实 SSHProcessManager,
/// 验证状态机转换、Start/Stop/Restart 语义、Stop All 与诊断信息保留。
@MainActor
final class TunnelServiceTests: XCTestCase {

    // MARK: - State transitions

    func test_start_transitions_to_starting_then_running() async throws {
        let (svc, fake, profiles) = makeService()
        let profile = makeProfile(name: "Production", alias: "production")
        profiles.add(profile)
        svc.registerProfile(profile)

        try await svc.start(profileID: profile.id)

        let tunnel = svc.tunnel(for: profile.id)
        XCTAssertNotNil(tunnel)
        XCTAssertTrue(
            tunnel?.state == .starting || tunnel?.state == .running,
            "expected starting/running, got \(String(describing: tunnel?.state))"
        )

        let launches = await fake.launches
        XCTAssertEqual(launches.count, 1)
        XCTAssertEqual(launches.first?.0, profile.id)
    }

    func test_stop_transitions_to_stopping_then_stopped() async throws {
        let (svc, fake, profiles) = makeService()
        let profile = makeProfile(name: "Production", alias: "production")
        profiles.add(profile)
        svc.registerProfile(profile)

        try await svc.start(profileID: profile.id)
        try await svc.stop(profileID: profile.id)

        let tunnel = svc.tunnel(for: profile.id)
        XCTAssertEqual(tunnel?.state, .stopped)

        let terminates = await fake.terminates
        XCTAssertEqual(terminates.count, 1)
    }

    func test_restart_stops_then_starts() async throws {
        let (svc, fake, profiles) = makeService()
        let profile = makeProfile(name: "Production", alias: "production")
        profiles.add(profile)
        svc.registerProfile(profile)

        try await svc.start(profileID: profile.id)
        try await svc.restart(profileID: profile.id)

        let launches = await fake.launches
        let terminates = await fake.terminates
        XCTAssertEqual(launches.count, 2, "restart should launch twice")
        XCTAssertGreaterThanOrEqual(terminates.count, 1, "restart should terminate at least once")
    }

    func test_late_exit_from_previous_start_is_ignored() async throws {
        let (svc, fake, profiles) = makeService()
        let profile = makeProfile(name: "Production", alias: "production")
        profiles.add(profile)
        svc.registerProfile(profile)

        try await svc.start(profileID: profile.id)
        let oldHandle = await fake.handle(at: 0)
        XCTAssertNotNil(oldHandle)

        // 第二次 start 启动一个新 generation;老 observation task 仍在跑。
        try await svc.start(profileID: profile.id)
        oldHandle?.emit(.terminated(exitCode: -15, reason: .exited))

        try await Task.sleep(nanoseconds: 100_000_000)
        let tunnel = svc.tunnel(for: profile.id)
        XCTAssertEqual(tunnel?.state, .running)
        XCTAssertNil(tunnel?.lastError)
    }

    func test_start_unknown_profile_throws() async {
        let (svc, _, _) = makeService()
        let unknownID = UUID()

        do {
            try await svc.start(profileID: unknownID)
            XCTFail("expected profileNotFound")
        } catch TunnelError.profileNotFound(let id) {
            XCTAssertEqual(id, unknownID)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_start_with_disabled_profile_does_nothing() async throws {
        let (svc, fake, profiles) = makeService()
        var profile = makeProfile(name: "Disabled", alias: "x")
        profile.behavior.enabled = false
        profiles.add(profile)
        svc.registerProfile(profile)

        try await svc.start(profileID: profile.id)
        let launches = await fake.launches
        XCTAssertEqual(launches.count, 0, "disabled profile should not be started")
    }

    func test_start_all_skips_disabled_profiles() async throws {
        let (svc, fake, profiles) = makeService()
        let p1 = makeProfile(name: "A", alias: "a")
        var p2 = makeProfile(name: "B", alias: "b")
        p2.behavior.enabled = false
        profiles.add(p1)
        profiles.add(p2)
        svc.registerProfile(p1)
        svc.registerProfile(p2)

        try await svc.startAll()
        let launches = await fake.launches
        XCTAssertEqual(launches.count, 1, "only enabled profile should start")
    }

    func test_stop_all_terminates_all_running_tunnels() async throws {
        let (svc, fake, profiles) = makeService()
        let p1 = makeProfile(name: "A", alias: "a")
        let p2 = makeProfile(name: "B", alias: "b")
        profiles.add(p1)
        profiles.add(p2)
        svc.registerProfile(p1)
        svc.registerProfile(p2)

        try await svc.start(profileID: p1.id)
        try await svc.start(profileID: p2.id)
        await svc.stopAll()

        let terminates = await fake.terminates
        XCTAssertGreaterThanOrEqual(terminates.count, 2)
    }

    /// 回归:`stopAll()` 后即使是 autoReconnect profile,state 也应该是 .stopped,
    /// 不进 .error / .reconnecting。
    func test_stop_all_does_not_trigger_autoreconnect() async throws {
        let (svc, _, profiles) = makeService()
        let p1 = makeProfile(name: "A", alias: "a")  // autoReconnect = true
        profiles.add(p1)
        svc.registerProfile(p1)
        svc._previewSetState(profileID: p1.id, state: .running, startedAt: Date())

        await svc.stopAll()

        let after = svc.tunnel(for: p1.id)?.state
        XCTAssertEqual(after, .stopped, "Stop All 后 state 应该是 .stopped,实际 \(String(describing: after))")
    }

    /// 锁定:stopAll 不再无差别覆盖 .error / .stopped 隧道的诊断信息。
    func test_stop_all_preserves_error_and_stopped_tunnel_state() async throws {
        let (svc, _, profiles) = makeService()
        let pErr = makeProfile(name: "broken", alias: "broken")
        let pStop = makeProfile(name: "done", alias: "done")
        let pRun = makeProfile(name: "live", alias: "live")
        profiles.add(pErr)
        profiles.add(pStop)
        profiles.add(pRun)
        svc.registerProfile(pErr)
        svc.registerProfile(pStop)
        svc.registerProfile(pRun)

        let now = Date()
        svc._previewSetState(
            profileID: pErr.id, state: .error,
            stoppedAt: now, lastError: .sshExited(code: 255, signal: nil, reason: .processExited))
        svc._previewSetState(
            profileID: pStop.id, state: .stopped,
            stoppedAt: now, lastError: nil)
        svc._previewSetState(
            profileID: pRun.id, state: .running,
            startedAt: now, stoppedAt: nil, lastError: nil)

        await svc.stopAll()

        // 活跃 → .stopped
        XCTAssertEqual(svc.tunnel(for: pRun.id)?.state, .stopped)
        XCTAssertNil(svc.tunnel(for: pRun.id)?.lastError)

        // .error 隧道保留
        XCTAssertEqual(svc.tunnel(for: pErr.id)?.state, .error)
        if case .sshExited(let code, _, _) = svc.tunnel(for: pErr.id)?.lastError {
            XCTAssertEqual(code, 255)
        } else {
            XCTFail("lastError 应该是 .sshExited(255),被 stopAll 误清了")
        }

        // .stopped 隧道保留
        XCTAssertEqual(svc.tunnel(for: pStop.id)?.state, .stopped)
    }

    // MARK: - Helpers

    private func makeService() -> (TunnelService, FakeSSHProcessManager, ProfileBag) {
        let fake = FakeSSHProcessManager()
        let portChecker = MockPortChecker()
        let validator = ProfileValidator()
        let logStore = TunnelLogStore()
        let profiles = ProfileBag()
        let svc = TunnelService(
            processManager: fake,
            portChecker: portChecker,
            validator: validator,
            logStore: logStore,
            reconnectService: FakeReconnectService(),
            managedPIDService: FakeManagedPIDService(),
            sshConfigProvider: nil,
            profileProvider: { await profiles.snapshot() }
        )
        return (svc, fake, profiles)
    }

    private func makeProfile(name: String, alias: String) -> Profile {
        Profile(
            name: name,
            sshHostAlias: alias,
            forwards: [PortForward(localHost: "127.0.0.1", localPort: 15432,
                                   remoteHost: "10.20.0.15", remotePort: 5432, label: nil)],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Test doubles

/// 线程安全的 profile 存储 — `ProfileProvider` 是 `@Sendable () async -> [Profile]`,
/// 测试需要从 MainActor 同步 `add()`,被 provider 异步 `snapshot()`。
private final class ProfileBag: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[UUID: Profile]>(initialState: [:])

    func add(_ profile: Profile) {
        lock.withLock { $0[profile.id] = profile }
    }

    func snapshot() async -> [Profile] {
        lock.withLock { Array($0.values) }
    }
}

private struct FakeReconnectService: ReconnectService {
    func markUserStop(profileID: UUID, stopped: Bool) async {}
    func onProcessExited(profileID: UUID) async -> ReconnectDecision { .skip }
    func schedule(profile: Profile) async throws -> UUID { UUID() }
    func cancel(profileID: UUID) async {}
}

private struct FakeManagedPIDService: ManagedPIDService {
    func track(pid: Int32, exePath: String, profileID: UUID) async throws {}
    func clear(pid: Int32) async throws {}
    func sweepOrphans() async throws -> Int { 0 }
}

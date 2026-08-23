import XCTest
@testable import JanusSSHTunnelEngine

/// TunnelManager 是整个 App 的核心 Application Service。
///
/// 测试策略:用 FakeSSHProcessManager 替换真实 SSHProcessManager,
/// 验证状态机转换、Start/Stop/Restart 语义、Start All/Stop All。
final class TunnelManagerTests: XCTestCase {

    // MARK: - State transitions

    func test_start_transitions_to_starting_then_running() async throws {
        let (mgr, fake) = makeManager()
        let profile = makeProfile(name: "Production", alias: "production")
        mgr.registerProfile(profile)

        try await mgr.start(profileID: profile.id)

        // start() 之后 Tunnel 应该进入 starting 或 running
        let tunnel = mgr.tunnel(for: profile.id)
        XCTAssertNotNil(tunnel)
        XCTAssertTrue(
            tunnel?.state == .starting || tunnel?.state == .running,
            "expected starting/running, got \(String(describing: tunnel?.state))"
        )

        // fake 收到了一个 launch 调用
        let launches = await fake.launches
        XCTAssertEqual(launches.count, 1)
        XCTAssertEqual(launches.first?.0, profile.id)
    }

    func test_stop_transitions_to_stopping_then_stopped() async throws {
        let (mgr, fake) = makeManager()
        let profile = makeProfile(name: "Production", alias: "production")
        mgr.registerProfile(profile)

        try await mgr.start(profileID: profile.id)
        try await mgr.stop(profileID: profile.id)

        let tunnel = mgr.tunnel(for: profile.id)
        XCTAssertEqual(tunnel?.state, .stopped)

        let terminates = await fake.terminates
        XCTAssertEqual(terminates.count, 1)
    }

    func test_restart_stops_then_starts() async throws {
        let (mgr, fake) = makeManager()
        let profile = makeProfile(name: "Production", alias: "production")
        mgr.registerProfile(profile)

        try await mgr.start(profileID: profile.id)
        try await mgr.restart(profileID: profile.id)

        let launches = await fake.launches
        let terminates = await fake.terminates
        XCTAssertEqual(launches.count, 2, "restart should launch twice")
        XCTAssertGreaterThanOrEqual(terminates.count, 1, "restart should terminate at least once")
    }

    func test_start_unknown_profile_throws() async {
        let (mgr, _) = makeManager()
        let unknownID = UUID()

        do {
            try await mgr.start(profileID: unknownID)
            XCTFail("expected profileNotFound")
        } catch TunnelError.profileNotFound(let id) {
            XCTAssertEqual(id, unknownID)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_start_with_disabled_profile_does_nothing() async throws {
        let (mgr, fake) = makeManager()
        var profile = makeProfile(name: "Disabled", alias: "x")
        profile.behavior.enabled = false
        mgr.registerProfile(profile)

        try await mgr.start(profileID: profile.id)
        let launches = await fake.launches
        XCTAssertEqual(launches.count, 0, "disabled profile should not be started")
    }

    func test_start_all_skips_disabled_profiles() async throws {
        let (mgr, fake) = makeManager()
        let p1 = makeProfile(name: "A", alias: "a")
        var p2 = makeProfile(name: "B", alias: "b")
        p2.behavior.enabled = false
        mgr.registerProfile(p1)
        mgr.registerProfile(p2)

        try await mgr.startAll()
        let launches = await fake.launches
        XCTAssertEqual(launches.count, 1, "only enabled profile should start")
        XCTAssertEqual(launches.first?.0, p1.id)
    }

    func test_stop_all_terminates_all_running_tunnels() async throws {
        let (mgr, fake) = makeManager()
        let p1 = makeProfile(name: "A", alias: "a")
        let p2 = makeProfile(name: "B", alias: "b")
        mgr.registerProfile(p1)
        mgr.registerProfile(p2)

        try await mgr.start(profileID: p1.id)
        try await mgr.start(profileID: p2.id)
        try await mgr.stopAll()

        let terminates = await fake.terminates
        XCTAssertEqual(terminates.count, 2)
    }

    // MARK: - Helpers

    private func makeManager() -> (TunnelManager, FakeSSHProcessManager) {
        let fake = FakeSSHProcessManager()
        let portChecker = MockPortChecker()
        let validator = ProfileValidator()
        let logStore = TunnelLogStore()
        let mgr = TunnelManager(
            processManager: fake,
            portChecker: portChecker,
            validator: validator,
            logStore: logStore
        )
        return (mgr, fake)
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

// MARK: - Fakes

final actor FakeSSHProcessManager: SSHProcessManaging {
    private(set) var launches: [(UUID, SSHCommand)] = []
    private(set) var terminates: [(UUID, Bool)] = []

    func launch(profileID: UUID, command: SSHCommand) async throws -> SSHProcessHandle {
        launches.append((profileID, command))
        return FakeSSHProcessHandle()
    }

    func terminate(profileID: UUID, reason: TerminationReason) async {
        terminates.append((profileID, true))
    }

    func terminateAll(reason: TerminationReason) async {
        for (id, _) in launches {
            terminates.append((id, true))
        }
    }

    func handle(for profileID: UUID) async -> SSHProcessHandle? {
        return FakeSSHProcessHandle()
    }
}

final class FakeSSHProcessHandle: SSHProcessHandle, @unchecked Sendable {
    func events() async -> AsyncStream<SSHProcess.Event> {
        AsyncStream { _ in }
    }

    func terminate(gracefully: Bool) async throws {}
    func terminateNow() {}
    func pid() async -> Int32? { return 12345 }
}
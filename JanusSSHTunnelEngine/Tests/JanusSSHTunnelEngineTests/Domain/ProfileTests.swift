import XCTest
@testable import JanusSSHTunnelEngine

/// Profile 是 Codable 持久化对象,代表 Janus 用户创建的"一组 SSH Tunnel 配置"。
/// Profile 故意不包含运行时状态(pid / status)— 运行时状态由 Tunnel 单独维护。
final class ProfileTests: XCTestCase {

    func test_profile_roundtrips_through_codable() throws {
        let original = Profile(
            name: "Production",
            sshHostAlias: "production",
            forwards: [
                PortForward(localHost: "127.0.0.1", localPort: 15432,
                            remoteHost: "10.20.0.15", remotePort: 5432, label: "postgres"),
                PortForward(localHost: "127.0.0.1", localPort: 16379,
                            remoteHost: "10.20.0.16", remotePort: 6379, label: "redis")
            ],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: true),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Profile.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func test_profile_excludes_runtime_state_from_persistence() throws {
        // Profile 必须不携带 TunnelState/pid 等运行时字段 — 否则会和真实运行态脱节
        let profile = Profile(
            name: "Staging",
            sshHostAlias: "staging",
            forwards: [],
            behavior: .defaults,
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(profile)
        let json = String(data: encoded, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("pid"))
        XCTAssertFalse(json.contains("state"))
        XCTAssertFalse(json.contains("startedAt"))
    }

    func test_profile_identifiable_by_id() {
        let p1 = Profile(name: "A", sshHostAlias: "a", forwards: [], behavior: .defaults,
                         createdAt: Date(), updatedAt: Date())
        let p2 = Profile(name: "A", sshHostAlias: "a", forwards: [], behavior: .defaults,
                         createdAt: Date(), updatedAt: Date())

        XCTAssertNotEqual(p1.id, p2.id)
    }

    func test_profile_snapshot_captures_runtime_immutable_copy() {
        // ProfileSnapshot 是 Tunnel 启动时拍下的不可变副本 — 之后改 Profile 不影响已运行的 Tunnel
        let p = Profile(
            name: "Production",
            sshHostAlias: "production",
            forwards: [
                PortForward(localHost: "127.0.0.1", localPort: 15432,
                            remoteHost: "10.20.0.15", remotePort: 5432, label: nil)
            ],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: Date(),
            updatedAt: Date()
        )

        let snapshot = ProfileSnapshot(p)

        XCTAssertEqual(snapshot.id, p.id)
        XCTAssertEqual(snapshot.name, p.name)
        XCTAssertEqual(snapshot.sshHostAlias, p.sshHostAlias)
        XCTAssertEqual(snapshot.forwards.count, 1)
        XCTAssertTrue(snapshot.autoReconnect)
        XCTAssertFalse(snapshot.autoStart)
    }
}
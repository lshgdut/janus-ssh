import XCTest
@testable import JanusSSHTunnelEngine

/// 覆盖 Profile.duplicated(takenNames:) 的所有命名碰撞路径 + 字段保留。
/// 命名算法: "<name> Copy" 后缀, 碰撞时空格分隔递增数字 ("Copy 2", "Copy 3", ...)。
/// 不补洞 — 选最小可用数字(Finder 行为)。
final class ProfileDuplicationTests: XCTestCase {

    // MARK: - Helpers

    private func makeProfile(
        name: String = "Production",
        sshHostAlias: String = "production",
        forwards: [PortForward] = [],
        behavior: Profile.Behavior = .defaults
    ) -> Profile {
        Profile(
            name: name,
            sshHostAlias: sshHostAlias,
            forwards: forwards,
            behavior: behavior
        )
    }

    // MARK: - Identity

    func test_duplicated_has_new_id_and_fresh_timestamps() {
        let source = makeProfile()
        let copy = source.duplicated(takenNames: [])
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertNotEqual(copy.createdAt, source.createdAt)
        XCTAssertNotEqual(copy.updatedAt, source.updatedAt)
    }

    func test_duplicated_preserves_all_other_fields() {
        let fwd = PortForward(localHost: "127.0.0.1", localPort: 15432,
                              remoteHost: "db", remotePort: 5432, label: "pg")
        let behavior = Profile.Behavior(enabled: false, autoReconnect: false, autoStart: true)
        let source = makeProfile(
            name: "Prod",
            sshHostAlias: "bastion",
            forwards: [fwd],
            behavior: behavior
        )
        let copy = source.duplicated(takenNames: [])
        XCTAssertEqual(copy.name, "Prod Copy")
        XCTAssertEqual(copy.sshHostAlias, source.sshHostAlias)
        XCTAssertEqual(copy.forwards, source.forwards)
        XCTAssertEqual(copy.behavior, source.behavior)
    }

    // MARK: - Naming: base case + collisions

    func test_name_no_collision_appends_Copy() {
        let copy = makeProfile(name: "Prod").duplicated(takenNames: ["Other"])
        XCTAssertEqual(copy.name, "Prod Copy")
    }

    func test_name_collision_increments_to_2() {
        let copy = makeProfile(name: "Prod").duplicated(takenNames: ["Prod Copy"])
        XCTAssertEqual(copy.name, "Prod Copy 2")
    }

    func test_name_collision_skips_2_finds_4_when_3_taken() {
        let copy = makeProfile(name: "Prod").duplicated(
            takenNames: ["Prod Copy", "Prod Copy 2", "Prod Copy 3"]
        )
        XCTAssertEqual(copy.name, "Prod Copy 4")
    }

    func test_name_collision_fills_gap_when_lower_number_free() {
        // "Prod Copy" 和 "Prod Copy 3" 占用, "Prod Copy 2" 空位应被填上
        let copy = makeProfile(name: "Prod").duplicated(
            takenNames: ["Prod Copy", "Prod Copy 3"]
        )
        XCTAssertEqual(copy.name, "Prod Copy 2")
    }

    func test_source_name_excluded_from_taken() {
        // 源 profile 名字本身在 taken 里, 不应该阻挡 "<name> Copy" 生成
        let copy = makeProfile(name: "Prod").duplicated(takenNames: ["Prod"])
        XCTAssertEqual(copy.name, "Prod Copy")
    }

    func test_empty_taken_set_returns_base_name() {
        let copy = makeProfile(name: "X").duplicated(takenNames: [])
        XCTAssertEqual(copy.name, "X Copy")
    }
}

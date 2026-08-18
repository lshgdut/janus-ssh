import XCTest
@testable import JanusSSHTunnelEngine

/// SSHCommandBuilder 是 Janus 唯一构造 `ssh` 命令的地方。
///
/// 关键不变性:
/// 1. 总是包含 `-o ExitOnForwardFailure=yes`(对齐原型 "Correctness" 章节)
/// 2. 总是包含 `-N`(不打开远程 shell)
/// 3. 每个 forward 一条 `-L <localHost:localPort:remoteHost:remotePort>`
/// 4. 最后是 sshHostAlias(位置参数)
/// 5. argv 数组直接传给 Process,**不经过 shell**
final class SSHCommandBuilderTests: XCTestCase {

    private let builder = SSHCommandBuilder()

    func test_build_includes_required_safe_flags() throws {
        let profile = makeProfile(forwards: [(15432, "10.20.0.15", 5432)])
        let cmd = try builder.build(profile: profile.snapshot)

        // 必须包含 -N(不打开 shell)和 ExitOnForwardFailure=yes
        XCTAssertTrue(cmd.arguments.contains("-N"))
        XCTAssertTrue(cmd.arguments.contains("ExitOnForwardFailure=yes"))
    }

    func test_build_includes_all_forwards_as_L_flags() throws {
        let profile = makeProfile(forwards: [
            (15432, "10.20.0.15", 5432),
            (16379, "10.20.0.16", 6379),
            (18080, "10.20.0.17", 8080)
        ])
        let cmd = try builder.build(profile: profile.snapshot)

        let lArgs = cmd.arguments.enumerated().compactMap { idx, arg -> String? in
            guard arg == "-L", idx + 1 < cmd.arguments.count else { return nil }
            return cmd.arguments[idx + 1]
        }
        XCTAssertEqual(lArgs, [
            "127.0.0.1:15432:10.20.0.15:5432",
            "127.0.0.1:16379:10.20.0.16:6379",
            "127.0.0.1:18080:10.20.0.17:8080"
        ])
    }

    func test_build_ends_with_ssh_host_alias() throws {
        let profile = makeProfile(alias: "production", forwards: [(1, "r", 1)])
        let cmd = try builder.build(profile: profile.snapshot)

        XCTAssertEqual(cmd.arguments.last, "production",
                       "sshHostAlias must be the trailing positional argument")
    }

    func test_build_uses_usr_bin_ssh() throws {
        let profile = makeProfile(forwards: [(1, "r", 1)])
        let cmd = try builder.build(profile: profile.snapshot)

        XCTAssertEqual(cmd.executable.path, "/usr/bin/ssh")
    }

    func test_build_throws_when_no_forwards() {
        let profile = makeProfile(forwards: [])
        XCTAssertThrowsError(try builder.build(profile: profile.snapshot)) { error in
            guard case SSHCommandBuilderError.noForwards = error else {
                XCTFail("expected .noForwards, got \(error)")
                return
            }
        }
    }

    func test_build_with_empty_forward_row_is_skipped() throws {
        // 表格中残留的"未填完"的 forward 行(localPort=0)应该跳过
        let profile = makeProfile(forwards: [
            (0, "", 0),  // 空行 — 应跳过
            (15432, "10.20.0.15", 5432)
        ])
        let cmd = try builder.build(profile: profile.snapshot)

        let lArgs = cmd.arguments.enumerated().compactMap { idx, arg -> String? in
            guard arg == "-L", idx + 1 < cmd.arguments.count else { return nil }
            return cmd.arguments[idx + 1]
        }
        XCTAssertEqual(lArgs.count, 1)
        XCTAssertEqual(lArgs.first, "127.0.0.1:15432:10.20.0.15:5432")
    }

    func test_production_profile_snapshot_matches_open_design() throws {
        // 直接对齐 OpenDesign 原型 dashboard.html 的 Production profile:
        //   3 forwards: 15432/16379/18080
        let profile = makeProfile(
            alias: "production",
            forwards: [
                (15432, "10.20.0.15", 5432),
                (16379, "10.20.0.16", 6379),
                (18080, "10.20.0.17", 8080)
            ]
        )

        let cmd = try builder.build(profile: profile.snapshot)

        // 关键不变量精确断言 — 这是 Tunnel 启动时实际执行的命令
        XCTAssertTrue(cmd.arguments.contains("-N"))
        XCTAssertTrue(cmd.arguments.contains("ExitOnForwardFailure=yes"))
        XCTAssertTrue(cmd.arguments.contains("127.0.0.1:15432:10.20.0.15:5432"))
        XCTAssertTrue(cmd.arguments.contains("127.0.0.1:16379:10.20.0.16:6379"))
        XCTAssertTrue(cmd.arguments.contains("127.0.0.1:18080:10.20.0.17:8080"))
        XCTAssertEqual(cmd.arguments.last, "production")
    }

    func test_build_does_not_pass_through_shell() throws {
        // 不变:命令通过 argv 数组执行,绝对不能出现 -c 或 sh
        let profile = makeProfile(forwards: [(1, "r", 1)])
        let cmd = try builder.build(profile: profile.snapshot)

        XCTAssertFalse(cmd.arguments.contains("-c"),
                       "must not shell out — use argv directly")
        XCTAssertFalse(cmd.executable.lastPathComponent.contains("sh"))
    }

    // MARK: - Helpers

    private struct TestProfile {
        let snapshot: ProfileSnapshot
    }

    private func makeProfile(
        alias: String = "test-host",
        forwards: [(UInt16, String, UInt16)]
    ) -> TestProfile {
        let pf = forwards.compactMap { p, h, r -> PortForward? in
            guard p != 0, !h.isEmpty, r != 0 else { return nil }
            return PortForward(localHost: "127.0.0.1", localPort: p,
                               remoteHost: h, remotePort: r, label: nil)
        }
        let profile = Profile(
            name: "Test",
            sshHostAlias: alias,
            forwards: pf,
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: Date(),
            updatedAt: Date()
        )
        return TestProfile(snapshot: ProfileSnapshot(profile))
    }
}
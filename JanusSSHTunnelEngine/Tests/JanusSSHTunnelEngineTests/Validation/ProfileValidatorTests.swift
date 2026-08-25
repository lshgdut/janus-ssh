import XCTest
@testable import JanusSSHTunnelEngine

/// ProfileValidator 强制原型 Editor 中的实时校验规则:
/// 1. name 非空
/// 2. sshHostAlias 在已知 hosts 内
/// 3. forwards ≥ 1
/// 4. 同 profile 内 localPort 不重复
/// 5. 跨 profile localPort 不冲突
/// 6. localPort 范围 1..65535
/// 7. localHost / remoteHost 非空
final class ProfileValidatorTests: XCTestCase {

    private let knownHosts: Set<String> = ["production", "staging", "bastion"]

    func test_valid_profile_produces_no_errors() {
        let profile = makeProfile(name: "Production", alias: "production", forwards: [
            (15432, "10.20.0.15", 5432)
        ])
        let issues = ProfileValidator().validate(profile, knownHosts: knownHosts)
        let errors = issues.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "unexpected errors: \(errors)")
    }

    func test_empty_name_is_an_error() {
        let profile = makeProfile(name: "", alias: "production", forwards: [
            (15432, "10.20.0.15", 5432)
        ])
        let issues = ProfileValidator().validate(profile, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.field == "name" })
    }

    func test_whitespace_only_name_is_an_error() {
        let profile = makeProfile(name: "   ", alias: "production", forwards: [
            (15432, "10.20.0.15", 5432)
        ])
        let issues = ProfileValidator().validate(profile, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.field == "name" })
    }

    func test_unknown_ssh_host_is_an_error() {
        let profile = makeProfile(name: "X", alias: "ghost-server", forwards: [
            (15432, "10.20.0.15", 5432)
        ])
        let issues = ProfileValidator().validate(profile, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.field == "sshHostAlias"
        })
    }

    func test_zero_forwards_is_an_error() {
        let profile = makeProfile(name: "X", alias: "production", forwards: [])
        let issues = ProfileValidator().validate(profile, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains {
            $0.severity == .error
            && $0.field == "forwards"
            && $0.message.contains("at least 1")
        })
    }

    func test_duplicate_local_port_within_same_profile_is_an_error() {
        // 对齐原型 Editor 里的 "同 Profile 内的 Local Port 15432 重复" 红框提示
        let profile = makeProfile(name: "X", alias: "production", forwards: [
            (15432, "10.20.0.15", 5432),
            (15432, "10.20.0.16", 6379)  // 重复 local port
        ])
        let issues = ProfileValidator().validate(profile, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains {
            $0.severity == .error
            && $0.message.contains("15432")
            && ($0.field?.contains("localPort") == true)
        })
    }

    func test_zero_local_port_is_an_error() {
        let profile = makeProfile(name: "X", alias: "production", forwards: [
            (0, "10.20.0.15", 5432)
        ])
        let issues = ProfileValidator().validate(profile, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains {
            $0.severity == .error
            && ($0.field?.contains("localPort") == true)
        })
    }

    func test_port_above_65535_is_an_error() {
        // 之前用 `70000` 字面量,但 `makeProfile(name:alias:forwards: [(UInt16, String, UInt16)])`
        // helper 强制 `localPort` 为 UInt16 — 编译期就 trap。换测 `0` 已覆盖 validator
        // 里 `if localPort == 0` 分支,跟"端口越界"是同一条规则的两个边界点。
        // 真正的"超过 UInt16 最大值"在运行时不可达,留给类型系统守住。
        let profile = makeProfile(name: "X", alias: "production", forwards: [
            (0, "10.20.0.15", 5432)
        ])
        let issues = ProfileValidator().validate(profile, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains { $0.severity == .error && ($0.field?.contains("localPort") == true) })
    }

    func test_empty_local_host_is_an_error() {
        var bad = makeProfile(name: "X", alias: "production", forwards: [
            (15432, "10.20.0.15", 5432)
        ])
        bad.forwards[0] = PortForward(
            localHost: "", localPort: 15432,
            remoteHost: "10.20.0.15", remotePort: 5432, label: nil
        )

        let issues = ProfileValidator().validate(bad, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains { $0.severity == .error && ($0.field?.contains("localHost") == true) })
    }

    func test_empty_remote_host_is_an_error() {
        var bad = makeProfile(name: "X", alias: "production", forwards: [
            (15432, "10.20.0.15", 5432)
        ])
        bad.forwards[0] = PortForward(
            localHost: "127.0.0.1", localPort: 15432,
            remoteHost: "", remotePort: 5432, label: nil
        )
        let issues = ProfileValidator().validate(bad, knownHosts: knownHosts)
        XCTAssertTrue(issues.contains { $0.severity == .error && ($0.field?.contains("remoteHost") == true) })
    }

    func test_cross_profile_local_port_conflict_is_an_error() {
        // 原型 Dashboard 中 Production/Staging 同时存在时必须做这个校验
        let existing: [Profile] = [
            makeProfile(name: "Production", alias: "production", forwards: [
                (15432, "10.20.0.15", 5432)
            ])
        ]
        let candidate = makeProfile(name: "Dev Mirror", alias: "staging", forwards: [
            (15432, "10.40.0.1", 5432)  // 同样的 local port
        ])

        let issues = ProfileValidator().validateForCrossProfileConflict(
            candidate, against: existing, excluding: nil
        )
        XCTAssertTrue(issues.contains {
            $0.severity == .error
            && $0.message.contains("15432")
        })
    }

    func test_cross_profile_check_excludes_self_when_editing() {
        // 编辑现有 profile 时,不能因为"自己和自己冲突"报错
        let id = UUID()
        let existing = makeProfile(name: "Production", alias: "production", forwards: [
            (15432, "10.20.0.15", 5432)
        ])
        let existingWithFixedID = Profile(
            id: id, name: existing.name, sshHostAlias: existing.sshHostAlias,
            forwards: existing.forwards, behavior: existing.behavior,
            createdAt: existing.createdAt, updatedAt: existing.updatedAt
        )

        let candidate = Profile(
            id: id, name: "Production (editing)", sshHostAlias: "production",
            forwards: [
                PortForward(localHost: "127.0.0.1", localPort: 15432,
                            remoteHost: "10.20.0.15", remotePort: 5432, label: nil)
            ],
            behavior: .defaults, createdAt: existing.createdAt, updatedAt: existing.updatedAt
        )

        let issues = ProfileValidator().validateForCrossProfileConflict(
            candidate, against: [existingWithFixedID], excluding: candidate.id
        )
        XCTAssertTrue(issues.isEmpty, "expected no issues, got: \(issues)")
    }

    func test_cross_profile_check_does_not_exclude_when_creating_new() {
        // 新建 profile 时必须把现有所有 profile 都视为冲突源
        let existing: [Profile] = [
            makeProfile(name: "Production", alias: "production", forwards: [
                (15432, "10.20.0.15", 5432)
            ])
        ]
        let newProfile = makeProfile(name: "Dev", alias: "staging", forwards: [
            (15432, "10.40.0.1", 5432)
        ])

        let issues = ProfileValidator().validateForCrossProfileConflict(
            newProfile, against: existing, excluding: nil
        )
        XCTAssertFalse(issues.isEmpty)
    }

    // MARK: - Helpers

    private func makeProfile(
        name: String,
        alias: String,
        forwards: [(UInt16, String, UInt16)]
    ) -> Profile {
        Profile(
            name: name,
            sshHostAlias: alias,
            forwards: forwards.map { port, host, rport in
                PortForward(
                    localHost: "127.0.0.1", localPort: port,
                    remoteHost: host, remotePort: rport, label: nil
                )
            },
            behavior: .defaults,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
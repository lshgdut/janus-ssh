import XCTest
@testable import JanusSSHTunnelEngine

/// JSONProfileRepository 是 App 启动时加载、用户编辑时保存的入口。
/// 关键行为:
/// - 文件不存在 → 抛 .fileNotFound(由 UI 走"首次启动"分支)
/// - 写入走 AtomicFileStore
/// - 每次保存生成 timestamped 备份,保留最近 10 个
final class JSONProfileRepositoryTests: XCTestCase {

    private var tempDir: URL!
    private var profilesURL: URL!
    private var backupDir: URL!
    private var repo: JSONProfileRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("janus-repo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        profilesURL = tempDir.appendingPathComponent("profiles.json")
        backupDir = tempDir.appendingPathComponent("backups")
        repo = JSONProfileRepository(
            fileURL: profilesURL,
            backupDirectory: backupDir,
            maxBackups: 10
        )
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Load

    func test_load_throws_when_file_missing() async {
        do {
            _ = try await repo.load()
            XCTFail("expected fileNotFound error")
        } catch RepositoryError.fileNotFound {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_load_returns_empty_when_file_is_empty_profiles() async throws {
        try await writeRaw(#"{"version":1,"profiles":[]}"#)
        let profiles = try await repo.load()
        XCTAssertTrue(profiles.isEmpty)
    }

    func test_load_returns_saved_profiles() async throws {
        let profile = makeProfile(name: "Production", alias: "production", forwards: [
            (15432, "10.20.0.15", 5432)
        ])
        try await repo.save([profile])

        let loaded = try await repo.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Production")
    }

    // MARK: - Save

    func test_save_persists_profiles() async throws {
        let profiles = [
            makeProfile(name: "A", alias: "host-a", forwards: [(1, "r", 1)]),
            makeProfile(name: "B", alias: "host-b", forwards: [(2, "r", 2)])
        ]
        try await repo.save(profiles)

        let reloaded = try await repo.load()
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(Set(reloaded.map { $0.name }), ["A", "B"])
    }

    func test_save_creates_backup() async throws {
        let p1 = makeProfile(name: "v1", alias: "host", forwards: [(1, "r", 1)])
        try await repo.save([p1])

        let p2 = makeProfile(name: "v2", alias: "host", forwards: [(1, "r", 1)])
        try await repo.save([p2])

        let backups = try FileManager.default.contentsOfDirectory(at: backupDir,
                                                                   includingPropertiesForKeys: nil)
        XCTAssertGreaterThanOrEqual(backups.count, 1, "at least one backup should exist")
    }

    func test_save_rotates_old_backups_beyond_max() async throws {
        // maxBackups = 10,我们保存 12 次,只应保留最近 10 个
        for i in 0..<12 {
            let p = makeProfile(name: "v\(i)", alias: "host", forwards: [(1, "r", 1)])
            try await repo.save([p])
            // 给文件创建留出时间差异(备份文件名含时间戳)
            try await Task.sleep(nanoseconds: 1_100_000)  // ~1ms
        }

        let backups = try FileManager.default.contentsOfDirectory(at: backupDir,
                                                                   includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 10,
                       "should keep exactly maxBackups entries, got \(backups.count)")
    }

    // MARK: - JSON envelope

    func test_save_wraps_profiles_in_versioned_envelope() async throws {
        let p = makeProfile(name: "X", alias: "host", forwards: [(1, "r", 1)])
        try await repo.save([p])

        let raw = try String(contentsOf: profilesURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"version\":1"))
        XCTAssertTrue(raw.contains("\"profiles\""))
    }

    // MARK: - Helpers

    private func writeRaw(_ content: String) async throws {
        try content.write(to: profilesURL, atomically: true, encoding: .utf8)
    }

    private func makeProfile(
        name: String,
        alias: String,
        forwards: [(UInt16, String, UInt16)]
    ) -> Profile {
        Profile(
            name: name,
            sshHostAlias: alias,
            forwards: forwards.map { p, h, rp in
                PortForward(localHost: "127.0.0.1", localPort: p,
                            remoteHost: h, remotePort: rp, label: nil)
            },
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
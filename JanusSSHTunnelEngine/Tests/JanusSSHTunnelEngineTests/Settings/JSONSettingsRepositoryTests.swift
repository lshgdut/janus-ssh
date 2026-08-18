import XCTest
@testable import JanusSSHTunnelEngine

/// JSONSettingsRepository 与 ProfileRepository 分离,允许 Settings 和 Profiles 独立演进。
/// 文件不存在时返回 AppSettings.defaults(首次启动)。
final class JSONSettingsRepositoryTests: XCTestCase {

    private var tempDir: URL!
    private var settingsURL: URL!
    private var repo: JSONSettingsRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("janus-settings-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        settingsURL = tempDir.appendingPathComponent("settings.json")
        repo = JSONSettingsRepository(fileURL: settingsURL)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func test_load_returns_defaults_when_file_missing() async throws {
        let settings = try await repo.load()
        XCTAssertEqual(settings, AppSettings.defaults)
    }

    func test_load_returns_saved_settings() async throws {
        var custom = AppSettings.defaults
        custom.general.launchAtLogin = true
        custom.ssh.configPath = "/custom/path/config"
        try await repo.save(custom)

        let loaded = try await repo.load()
        XCTAssertEqual(loaded, custom)
    }

    func test_save_creates_file_with_version_envelope() async throws {
        try await repo.save(AppSettings.defaults)

        let raw = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"version\":1"))
        XCTAssertTrue(raw.contains("\"general\""))
        XCTAssertTrue(raw.contains("\"tunnel\""))
    }

    func test_defaults_have_safe_reconnect_policy() {
        // Defaults must not accidentally disable Auto Reconnect — that's the #1 feature
        XCTAssertTrue(AppSettings.defaults.tunnel.defaultAutoReconnect)
        XCTAssertTrue(AppSettings.defaults.tunnel.exitOnForwardFailure)
        XCTAssertEqual(AppSettings.defaults.tunnel.backoffPolicy.initialDelayMs, 1000)
        XCTAssertEqual(AppSettings.defaults.tunnel.backoffPolicy.maxDelayMs, 30000)
    }

    func test_settings_are_codable_roundtrip() throws {
        let original = AppSettings.defaults
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
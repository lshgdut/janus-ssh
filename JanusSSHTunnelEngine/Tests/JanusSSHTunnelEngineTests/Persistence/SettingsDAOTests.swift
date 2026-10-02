import XCTest
@testable import JanusSSHTunnelEngine

final class SettingsDAOTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsDAOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func test_default_settings_round_trip() async throws {
        let store = AtomicFileStore(directory: tmpDir)
        let dao = JSONSettingsDAOImpl(store: store, directory: tmpDir)
        let original = AppSettings.defaults

        try await dao.save(original)
        let loaded = try await dao.load()

        XCTAssertEqual(loaded, original)
    }

    func test_load_returns_defaults_when_file_missing() async throws {
        let store = AtomicFileStore(directory: tmpDir)
        let dao = JSONSettingsDAOImpl(store: store, directory: tmpDir)

        let loaded = try await dao.load()

        XCTAssertEqual(loaded, AppSettings.defaults)
    }
}

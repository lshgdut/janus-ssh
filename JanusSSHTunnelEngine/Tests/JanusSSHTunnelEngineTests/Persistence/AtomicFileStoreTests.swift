import XCTest
@testable import JanusSSHTunnelEngine

/// AtomicFileStore 保证配置文件写入的原子性:
/// 1. 写入 .tmp 文件
/// 2. fsync
/// 3. 把当前文件改名为 .bak
/// 4. rename .tmp → 目标文件
/// 5. fsync 父目录
///
/// 这样即使 App crash,目标文件要么是旧版要么是新版,不会有损坏的中间态。
final class AtomicFileStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("janus-atomic-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func test_write_creates_file_at_target_path() async throws {
        let store = AtomicFileStore()
        let url = tempDir.appendingPathComponent("config.json")

        try await store.write(Data("hello".utf8), to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(content, "hello")
    }

    func test_write_does_not_leave_temp_file_on_success() async throws {
        let store = AtomicFileStore()
        let url = tempDir.appendingPathComponent("config.json")

        try await store.write(Data("hello".utf8), to: url)

        let tmpURL = url.appendingPathExtension("tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpURL.path),
                       "temp file must be cleaned up after successful rename")
    }

    func test_write_overwrites_existing_file() async throws {
        let store = AtomicFileStore()
        let url = tempDir.appendingPathComponent("config.json")

        try await store.write(Data("v1".utf8), to: url)
        try await store.write(Data("v2".utf8), to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(content, "v2")
    }

    func test_write_creates_backup_of_previous_file() async throws {
        let store = AtomicFileStore()
        let url = tempDir.appendingPathComponent("config.json")

        try await store.write(Data("v1".utf8), to: url)
        try await store.write(Data("v2".utf8), to: url)

        let bakURL = url.deletingPathExtension().appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path),
                      "previous file should have been preserved as .bak")
        let bakContent = try String(contentsOf: bakURL, encoding: .utf8)
        XCTAssertEqual(bakContent, "v1")
    }

    func test_write_first_time_does_not_create_bak() async throws {
        // 首次写入时不存在"前一个版本",不应该凭空创建 .bak
        let store = AtomicFileStore()
        let url = tempDir.appendingPathComponent("config.json")

        try await store.write(Data("first".utf8), to: url)

        let bakURL = url.deletingPathExtension().appendingPathExtension("bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bakURL.path),
                       "no .bak should exist on first write")
    }

    func test_write_to_nonexistent_directory_throws() async {
        let store = AtomicFileStore()
        let badURL = URL(fileURLWithPath: "/this/path/does/not/exist/config.json")

        do {
            try await store.write(Data("hello".utf8), to: badURL)
            XCTFail("expected error")
        } catch {
            // Expected — non-existent parent directory should propagate error
        }
    }
}
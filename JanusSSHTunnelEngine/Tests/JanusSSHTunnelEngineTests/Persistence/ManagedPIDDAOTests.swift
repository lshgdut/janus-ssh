import XCTest
@testable import JanusSSHTunnelEngine

final class ManagedPIDDAOTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManagedPIDDAOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func test_upsert_then_delete() async throws {
        let store = AtomicFileStore(directory: tmpDir)
        let dao = JSONManagedPIDDAOImpl(store: store, directory: tmpDir)
        let entry = ManagedPID(
            profileID: UUID(),
            pid: 1234,
            startedAt: Date(),
            exePath: "/usr/bin/ssh"
        )

        try await dao.upsert(entry)
        let loaded = try await dao.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.pid, 1234)

        try await dao.delete(pid: 1234)
        let after = try await dao.loadAll()
        XCTAssertTrue(after.isEmpty)
    }

    func test_upsert_replaces_by_pid() async throws {
        let store = AtomicFileStore(directory: tmpDir)
        let dao = JSONManagedPIDDAOImpl(store: store, directory: tmpDir)
        let profileID = UUID()
        let original = ManagedPID(profileID: profileID, pid: 7777, startedAt: Date(), exePath: "/old")
        let replacement = ManagedPID(profileID: profileID, pid: 7777, startedAt: Date(), exePath: "/new")

        try await dao.upsert(original)
        try await dao.upsert(replacement)

        let loaded = try await dao.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.exePath, "/new")
    }

    func test_load_returns_empty_when_file_missing() async throws {
        let store = AtomicFileStore(directory: tmpDir)
        let dao = JSONManagedPIDDAOImpl(store: store, directory: tmpDir)

        let loaded = try await dao.loadAll()

        XCTAssertTrue(loaded.isEmpty)
    }
}

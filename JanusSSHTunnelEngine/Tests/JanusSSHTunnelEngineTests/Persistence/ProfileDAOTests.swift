import XCTest
@testable import JanusSSHTunnelEngine

final class ProfileDAOTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileDAOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func test_upsert_then_loadAll_returns_profile() async throws {
        let store = AtomicFileStore(directory: tmpDir)
        let dao = JSONProfileDAOImpl(store: store, directory: tmpDir)
        let profile = Profile(name: "p1", sshHostAlias: "h1", forwards: [], behavior: .defaults)

        try await dao.upsert(profile)
        let loaded = try await dao.loadAll()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, profile.id)
    }

    func test_delete_removes_profile() async throws {
        let store = AtomicFileStore(directory: tmpDir)
        let dao = JSONProfileDAOImpl(store: store, directory: tmpDir)
        let profile = Profile(name: "p1", sshHostAlias: "h1", forwards: [], behavior: .defaults)
        try await dao.upsert(profile)

        try await dao.delete(id: profile.id)
        let loaded = try await dao.loadAll()

        XCTAssertTrue(loaded.isEmpty)
    }

    func test_exists_returns_true_for_duplicate_name() async throws {
        let store = AtomicFileStore(directory: tmpDir)
        let dao = JSONProfileDAOImpl(store: store, directory: tmpDir)
        let profile = Profile(name: "p1", sshHostAlias: "h1", forwards: [], behavior: .defaults)
        try await dao.upsert(profile)

        let exists = try await dao.exists(name: "p1", excluding: nil)
        XCTAssertTrue(exists)

        let excludingSelf = try await dao.exists(name: "p1", excluding: profile.id)
        XCTAssertFalse(excludingSelf)
    }
}

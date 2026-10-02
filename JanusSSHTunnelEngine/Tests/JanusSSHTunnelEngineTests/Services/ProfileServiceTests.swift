import XCTest
@testable import JanusSSHTunnelEngine

@MainActor
final class ProfileServiceTests: XCTestCase {
    func test_create_appends_profile() async throws {
        let dao = InMemoryProfileDAO()
        let service = ProfileServiceImpl(dao: dao)

        let profile = try await service.create(
            name: "p1",
            sshHostAlias: "h1",
            forwards: [],
            behavior: .defaults
        )

        XCTAssertEqual(service.profiles.count, 1)
        XCTAssertEqual(service.profiles.first?.id, profile.id)
        let stored = try await dao.loadAll()
        XCTAssertEqual(stored.first?.name, "p1")
    }

    func test_create_duplicate_name_throws() async throws {
        let dao = InMemoryProfileDAO()
        let service = ProfileServiceImpl(dao: dao)
        _ = try await service.create(name: "p1", sshHostAlias: "h1", forwards: [], behavior: .defaults)

        do {
            _ = try await service.create(name: "p1", sshHostAlias: "h2", forwards: [], behavior: .defaults)
            XCTFail("expected throw")
        } catch let error as AppError {
            guard case .duplicateProfileName(let name) = error else {
                XCTFail("wrong case: \(error)"); return
            }
            XCTAssertEqual(name, "p1")
        }
    }

    func test_update_modifies_existing() async throws {
        let dao = InMemoryProfileDAO()
        let service = ProfileServiceImpl(dao: dao)
        var profile = try await service.create(name: "p1", sshHostAlias: "h1", forwards: [], behavior: .defaults)
        profile.name = "p1-renamed"

        try await service.update(profile)

        XCTAssertEqual(service.profiles.first?.name, "p1-renamed")
    }

    func test_delete_removes_profile() async throws {
        let dao = InMemoryProfileDAO()
        let service = ProfileServiceImpl(dao: dao)
        let profile = try await service.create(name: "p1", sshHostAlias: "h1", forwards: [], behavior: .defaults)

        try await service.delete(id: profile.id)

        XCTAssertTrue(service.profiles.isEmpty)
    }

    func test_duplicate_appends_with_unique_name() async throws {
        let dao = InMemoryProfileDAO()
        let service = ProfileServiceImpl(dao: dao)
        let original = try await service.create(name: "p1", sshHostAlias: "h1", forwards: [], behavior: .defaults)

        let copy = try await service.duplicate(id: original.id, name: nil)

        XCTAssertEqual(service.profiles.count, 2)
        XCTAssertEqual(copy.name, "p1 Copy")
        XCTAssertNotEqual(copy.id, original.id)
    }

    func test_validate_returns_issues_for_invalid_profile() async throws {
        let dao = InMemoryProfileDAO()
        let service = ProfileServiceImpl(dao: dao)
        let invalid = Profile(name: "", sshHostAlias: "", forwards: [], behavior: .defaults)

        let issues = try await service.validate(invalid)

        XCTAssertFalse(issues.isEmpty)
    }
}

private actor InMemoryProfileDAO: ProfileDAO {
    private var storage: [Profile] = []
    func loadAll() async throws -> [Profile] { storage }
    func upsert(_ profile: Profile) async throws {
        if let idx = storage.firstIndex(where: { $0.id == profile.id }) {
            storage[idx] = profile
        } else {
            storage.append(profile)
        }
    }
    func delete(id: UUID) async throws { storage.removeAll { $0.id == id } }
    func exists(name: String, excluding: UUID?) async throws -> Bool {
        storage.contains { $0.name == name && $0.id != excluding }
    }
}
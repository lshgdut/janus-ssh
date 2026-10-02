import XCTest
@testable import JanusSSHTunnelEngine

@MainActor
final class SettingsServiceTests: XCTestCase {
    func test_update_persists_changes() async throws {
        let dao = InMemorySettingsDAO()
        let service = SettingsServiceImpl(dao: dao)
        try await service.bootstrap()

        try await service.update { $0.general.theme = .dark }

        XCTAssertEqual(service.settings.general.theme, .dark)
        let stored = try await dao.load()
        XCTAssertEqual(stored.general.theme, .dark)
    }

    func test_update_no_change_does_not_write() async throws {
        let dao = InMemorySettingsDAO()
        let service = SettingsServiceImpl(dao: dao)
        try await service.bootstrap()

        // No-op mutation — same value as current settings.
        try await service.update { _ in }

        let writes = await dao.saves
        XCTAssertEqual(writes, 0)
    }
}

private actor InMemorySettingsDAO: SettingsDAO {
    private var storage: AppSettings = .defaults
    private var writeCount = 0
    func load() async throws -> AppSettings { storage }
    func save(_ settings: AppSettings) async throws {
        storage = settings
        writeCount += 1
    }
    var saves: Int { writeCount }
}

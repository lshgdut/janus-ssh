import XCTest
@testable import JanusSSHTunnelEngine

final class JSONMigratorTests: XCTestCase {
    func test_migrate_v1_envelope_returns_unchanged() async throws {
        let v1Data = #"""
        {"version":1,"updatedAt":"2024-01-01T00:00:00Z","profiles":[]}
        """#.data(using: .utf8)!

        let migrator = JSONMigrator(supportedVersion: .v1)
        let result = try await migrator.migrate(envelope: v1Data)
        let decoded = try JSONDecoder().decode(SchemaVersionEnvelopeProbe.self, from: result)
        XCTAssertEqual(decoded.version, 1)
    }

    func test_migrate_too_new_throws_schemaVersionTooNew() async {
        let futureData = #"""
        {"version":99,"updatedAt":"2024-01-01T00:00:00Z","profiles":[]}
        """#.data(using: .utf8)!

        let migrator = JSONMigrator(supportedVersion: .v1)
        do {
            _ = try await migrator.migrate(envelope: futureData)
            XCTFail("expected throw")
        } catch let error as AppError {
            guard case .schemaVersionTooNew(let found, let supported) = error else {
                XCTFail("wrong case: \(error)"); return
            }
            XCTAssertEqual(found, 99)
            XCTAssertEqual(supported, 1)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private struct SchemaVersionEnvelopeProbe: Decodable {
    let version: Int
}
import XCTest
@testable import JanusSSHTunnelEngine

/// 未来 schema 演进时,Migration 必须能把旧版本读出来。
/// M2 只覆盖 v1,但必须把迁移框架留出来。
final class MigrationTests: XCTestCase {

    func test_current_schema_version_is_one() {
        XCTAssertEqual(SchemaVersion.current, .v1)
    }

    func test_v1_envelope_decodes_without_migration() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-08-18T15:42:02Z",
          "profiles": []
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(ProfileEnvelope.self, from: json)
        XCTAssertEqual(envelope.version, 1)
        XCTAssertTrue(envelope.profiles.isEmpty)
    }

    func test_unknown_version_is_rejected() {
        // 防止"未来版本的备份被当前 App 静默接受"
        let json = """
        {
          "version": 999,
          "profiles": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ProfileEnvelope.self, from: json))
    }

    func test_missing_version_field_is_treated_as_v1() throws {
        // 老配置文件可能没有 version 字段 — 视为 v1
        let json = """
        {
          "profiles": []
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(ProfileEnvelope.self, from: json)
        XCTAssertEqual(envelope.version, 1)
    }
}
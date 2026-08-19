import Foundation

/// 数据 schema 版本 — 用于 ProfileEnvelope 演进时的迁移判断
public enum SchemaVersion: Int, Codable, Sendable {
    case v1 = 1

    public static let current: SchemaVersion = .v1
}

/// Profile 文件的 JSON 顶层结构。
///
/// `version` 缺失时视为 v1(向后兼容)。
public struct ProfileEnvelope: Codable, Equatable, Sendable {
    var version: Int
    var updatedAt: Date?
    var profiles: [Profile]

    public init(profiles: [Profile], updatedAt: Date? = nil) {
        self.version = SchemaVersion.current.rawValue
        self.updatedAt = updatedAt
        self.profiles = profiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 缺 version 视为 v1 — 与测试 test_missing_version_field_is_treated_as_v1 一致
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.profiles = try container.decode([Profile].self, forKey: .profiles)
    }
}
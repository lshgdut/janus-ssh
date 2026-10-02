import Foundation

public actor JSONMigrator {
    public struct Transformation: Sendable {
        public let from: SchemaVersion
        public let to: SchemaVersion
        public let transform: @Sendable (Data) throws -> Data

        public init(
            from: SchemaVersion,
            to: SchemaVersion,
            transform: @escaping @Sendable (Data) throws -> Data
        ) {
            self.from = from
            self.to = to
            self.transform = transform
        }
    }

    private let supportedVersion: SchemaVersion

    /// 升序链；当前为空（v1 → v1 无需转换）。
    /// 未来新增 v2 时按 (v1 → v2, transform) 注册即可。
    public static let transformations: [Transformation] = []

    public init(supportedVersion: SchemaVersion) {
        self.supportedVersion = supportedVersion
    }

    public func migrate(envelope: Data) throws -> Data {
        var current = try Self.decodeVersion(envelope)
        guard current <= supportedVersion else {
            throw AppError.schemaVersionTooNew(
                found: current.rawValue,
                supported: supportedVersion.rawValue
            )
        }
        var data = envelope
        for transformation in Self.transformations where transformation.from == current {
            data = try transformation.transform(data)
            let newVersion = try Self.decodeVersion(data)
            guard newVersion == transformation.to else {
                throw AppError.decode(path: "envelope", source: "transformation expected to advance to v\(transformation.to.rawValue) but produced v\(newVersion.rawValue)")
            }
            current = newVersion
        }
        return data
    }

    private static func decodeVersion(_ data: Data) throws -> SchemaVersion {
        struct Probe: Decodable { let version: Int }
        do {
            let raw = try JSONDecoder().decode(Probe.self, from: data).version
            guard let version = SchemaVersion(rawValue: raw) else {
                throw AppError.schemaVersionTooNew(found: raw, supported: SchemaVersion.current.rawValue)
            }
            return version
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.decode(path: "envelope", source: String(describing: error))
        }
    }
}
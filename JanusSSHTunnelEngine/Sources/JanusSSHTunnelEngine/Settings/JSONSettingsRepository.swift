import Foundation

/// Settings 持久化协议
protocol SettingsRepository: Sendable {
    /// 文件不存在时返回 `AppSettings.defaults`(首次启动)
    func load() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
}

/// JSON + Atomic Write 的 Settings 实现
actor JSONSettingsRepository: SettingsRepository {

    private let fileURL: URL
    private let store: AtomicFileStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL, store: AtomicFileStore = AtomicFileStore()) {
        self.fileURL = fileURL
        self.store = store

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func load() async throws -> AppSettings {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return AppSettings.defaults
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            // 损坏的 settings 文件 — 退回 defaults,不阻塞启动
            return AppSettings.defaults
        }
    }

    func save(_ settings: AppSettings) async throws {
        let data = try encoder.encode(settings)
        try await store.write(data, to: fileURL)
    }
}
import Foundation

/// Settings 数据访问对象。
///
/// 与 `SettingsRepository` 接口相同 — 但语义上 DAO 是给 ViewModel
/// 直接读写单条记录(`AppSettings`)用,Repository 是给上层拼装整套
/// 备份 / 导入导出用。两个暂时并存,Task 7 删除 Repository。
public protocol SettingsDAO: Sendable {
    func load() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
}

/// JSON + Atomic Write 的实现。
public actor JSONSettingsDAOImpl: SettingsDAO {

    private let store: AtomicFileStore
    private let fileURL: URL
    private var cache: AppSettings?

    public init(store: AtomicFileStore, directory: URL = AppPaths.applicationSupport) {
        self.store = store
        self.fileURL = directory.appendingPathComponent("settings.json")
    }

    public func load() async throws -> AppSettings {
        if let cache { return cache }
        // 文件不存在 = 首次启动 — 返回 `AppSettings.defaults`,不抛错。
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = AppSettings.defaults
            cache = defaults
            return defaults
        }
        let settings: AppSettings = try await store.read(
            AppSettings.self,
            from: fileURL
        )
        cache = settings
        return settings
    }

    public func save(_ settings: AppSettings) async throws {
        try await store.write(settings, to: fileURL)
        cache = settings
    }
}

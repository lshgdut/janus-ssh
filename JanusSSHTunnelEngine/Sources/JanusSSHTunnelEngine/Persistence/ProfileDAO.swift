import Foundation

/// Profile 数据访问对象 — 抽象层让未来可以切换到 SQLite 等后端。
///
/// 与 `ProfileRepository` 的区别:
/// - DAO 接口颗粒更细(`upsert` / `delete` / `exists`),不直接操作整张
///   `[Profile]` 数组 — 给上层 ViewModel / AppContainer 拼装业务逻辑用。
/// - Repository 是面向"整批替换"的语义,DAO 是面向"单条记录"。
///
/// 两者暂时并存 — Task 7 删除 Repository,只剩 DAO。
public protocol ProfileDAO: Sendable {
    func loadAll() async throws -> [Profile]
    func upsert(_ profile: Profile) async throws
    func delete(id: UUID) async throws
    func exists(name: String, excluding: UUID?) async throws -> Bool
}

/// JSON + Atomic Write 的实现 — 单 actor 串行化所有访问。
///
/// `directory` 默认指向 `AppPaths.applicationSupport`。测试可以注入
/// 临时目录:`JSONProfileDAOImpl(store: store, directory: tmpDir)`。
public actor JSONProfileDAOImpl: ProfileDAO {

    private let store: AtomicFileStore
    private let fileURL: URL
    private var cache: [Profile]?

    public init(store: AtomicFileStore, directory: URL = AppPaths.applicationSupport) {
        self.store = store
        self.fileURL = directory.appendingPathComponent("profiles.json")
    }

    public func loadAll() async throws -> [Profile] {
        if let cache { return cache }
        // 文件不存在 = 首次启动 — 返回空数组而不是抛错。
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }
        let envelope: ProfileEnvelope = try await store.read(
            ProfileEnvelope.self,
            from: fileURL
        )
        cache = envelope.profiles
        return envelope.profiles
    }

    public func upsert(_ profile: Profile) async throws {
        var profiles = try await loadAll()
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        try await persist(profiles)
    }

    public func delete(id: UUID) async throws {
        var profiles = try await loadAll()
        profiles.removeAll { $0.id == id }
        try await persist(profiles)
    }

    public func exists(name: String, excluding: UUID?) async throws -> Bool {
        let profiles = try await loadAll()
        return profiles.contains { profile in
            profile.name == name && profile.id != excluding
        }
    }

    private func persist(_ profiles: [Profile]) async throws {
        let envelope = ProfileEnvelope(profiles: profiles, updatedAt: Date())
        try await store.write(envelope, to: fileURL)
        cache = profiles
    }
}

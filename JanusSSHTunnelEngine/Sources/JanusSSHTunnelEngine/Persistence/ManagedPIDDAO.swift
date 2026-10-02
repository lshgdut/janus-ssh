import Foundation

/// ManagedPID 数据访问对象 — App 启动过的 SSH 子进程 PID 列表。
///
/// 与 `ManagedPIDStore` 的区别:
/// - `ManagedPIDStore` 是 actor + 同时持有"实际进程 sweep 行为"
///   (发 SIGTERM / SIGKILL),是 Domain 服务层。
/// - `ManagedPIDDAO` 只关心 CRUD 持久化,不碰进程本身。
///
/// 两者并存,DAO 给上层 ViewModel / 统计 / 调试用,Store 保留 sweep 行为。
public protocol ManagedPIDDAO: Sendable {
    func loadAll() async throws -> [ManagedPID]
    func upsert(_ entry: ManagedPID) async throws
    func delete(pid: Int32) async throws
}

/// JSON + Atomic Write 的实现 — 文件是裸数组。
public actor JSONManagedPIDDAOImpl: ManagedPIDDAO {

    private let store: AtomicFileStore
    private let fileURL: URL
    private var cache: [ManagedPID]?

    public init(store: AtomicFileStore, directory: URL = AppPaths.applicationSupport) {
        self.store = store
        self.fileURL = directory.appendingPathComponent("managed_pids.json")
    }

    public func loadAll() async throws -> [ManagedPID] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }
        let entries: [ManagedPID] = try await store.read(
            [ManagedPID].self,
            from: fileURL
        )
        cache = entries
        return entries
    }

    public func upsert(_ entry: ManagedPID) async throws {
        var entries = try await loadAll()
        if let idx = entries.firstIndex(where: { $0.pid == entry.pid }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        try await persist(entries)
    }

    public func delete(pid: Int32) async throws {
        var entries = try await loadAll()
        entries.removeAll { $0.pid == pid }
        try await persist(entries)
    }

    private func persist(_ entries: [ManagedPID]) async throws {
        try await store.write(entries, to: fileURL)
        cache = entries
    }
}

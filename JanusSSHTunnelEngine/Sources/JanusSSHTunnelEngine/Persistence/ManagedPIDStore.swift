import Foundation
import Darwin

/// 持久化记录 App 启动过的 SSH 子进程 PID,用于:
/// 1. App 被 force-quit / crash 时,SSh 子进程变成孤儿继续运行,占用本地端口
/// 2. 下次 App 启动时扫描该列表,把还活着的进程全部 SIGKILL
///
/// 文件位置:用户配置的 app support 目录下的 `managed_pids.json`。
public actor ManagedPIDStore {

    public struct Entry: Codable, Equatable, Sendable {
        public let profileID: UUID
        public let pid: Int32
        public let startedAt: Date

        public init(profileID: UUID, pid: Int32, startedAt: Date) {
            self.profileID = profileID
            self.pid = pid
            self.startedAt = startedAt
        }
    }

    private let fileURL: URL
    private let store: AtomicFileStore
    private var entries: [Entry]

    public init(fileURL: URL, store: AtomicFileStore = AtomicFileStore()) {
        self.fileURL = fileURL
        self.store = store
        self.entries = []
    }

    /// 加载持久化的 PID 列表
    public func load() async {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([Entry].self, from: data)) ?? []
        } catch {
            entries = []
        }
    }

    /// 记录一个新启动的 SSH 进程
    public func record(profileID: UUID, pid: Int32) async {
        let entry = Entry(profileID: profileID, pid: pid, startedAt: Date())
        // 同一个 profile 重启时,旧的 pid 记录会被新的替换
        entries.removeAll { $0.profileID == profileID }
        entries.append(entry)
        await persist()
    }

    /// 移除某个 profile 的 PID 记录(进程已结束)
    public func remove(profileID: UUID) async {
        let before = entries.count
        entries.removeAll { $0.profileID == profileID }
        if entries.count != before {
            await persist()
        }
    }

    /// 清理所有记录(例如 reset profiles 后)
    public func clear() async {
        guard !entries.isEmpty else { return }
        entries = []
        await persist()
    }

    /// 扫描当前 entries,杀掉还活着的进程,返回被杀掉的 (profileID, pid) 列表
    /// 用于 App 启动时清理上一会话的孤儿进程。
    @discardableResult
    public func sweep() async -> [(profileID: UUID, pid: Int32)] {
        var killed: [(profileID: UUID, pid: Int32)] = []
        let survivors: [Entry] = []

        for entry in entries {
            if isAlive(pid: entry.pid) {
                // 先 SIGTERM,1 秒后还活着就 SIGKILL
                _ = kill(entry.pid, SIGTERM)
                try? await Task.sleep(nanoseconds: 500_000_000)
                if isAlive(pid: entry.pid) {
                    _ = kill(entry.pid, SIGKILL)
                }
                killed.append((entry.profileID, entry.pid))
            }
            // 无论是否还活着,都不再保留这条记录 — sweep 之后从干净状态开始
        }

        if !killed.isEmpty {
            entries = survivors
            await persist()
        }

        return killed
    }

    /// 当前记录的所有 pid
    public var currentPIDs: [Entry] { entries }

    private func isAlive(pid: Int32) -> Bool {
        // kill(pid, 0) 不发信号,只检查进程是否存在 / 当前用户能否发信号
        // 返回 0 → 进程存在;返回 -1 + ESRCH → 进程不存在
        return kill(pid, 0) == 0
    }

    private func persist() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? await store.write(data, to: fileURL)
    }
}
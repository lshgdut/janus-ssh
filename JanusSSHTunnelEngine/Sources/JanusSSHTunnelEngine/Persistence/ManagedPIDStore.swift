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
        /// 进程可执行文件路径 — 启动时通过 `proc_pidpath` 记录,sweep 时用来
        /// 验证 PID 没被 OS recycle 出去交给别的进程(否则 SIGKILL 会误杀
        /// 用户正在跑的 `ssh` 或别的同名进程)。旧 JSON 文件没有这字段,
        /// Codable 用 decodeIfPresent 容忍 — 这部分条目降级到"只查 liveness"。
        public let exePath: String?

        public init(profileID: UUID, pid: Int32, startedAt: Date, exePath: String? = nil) {
            self.profileID = profileID
            self.pid = pid
            self.startedAt = startedAt
            self.exePath = exePath
        }

        // 自定义解码 — 让旧 managed_pids.json(没有 exePath 字段)能继续工作,
        // 缺字段时为 nil,sweep 时只对带 fingerprint 的条目做强校验。
        enum CodingKeys: String, CodingKey {
            case profileID, pid, startedAt, exePath
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            profileID  = try c.decode(UUID.self, forKey: .profileID)
            pid        = try c.decode(Int32.self, forKey: .pid)
            startedAt  = try c.decode(Date.self, forKey: .startedAt)
            exePath    = try c.decodeIfPresent(String.self, forKey: .exePath)
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
        // 抓 exePath 当 fingerprint — sweep 时用来验证 PID 没被 recycle。
        let exePath = Self.executablePath(for: pid)
        let entry = Entry(profileID: profileID, pid: pid, startedAt: Date(), exePath: exePath)
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

        for entry in entries {
            guard isAlive(pid: entry.pid) else { continue }

            // PID 所有权校验 — 防止误杀。
            // 只查 liveness 不够:Janus force-quit 后,OS 会把这个 PID 重新分配
            // 给另一个进程(用户的 `ssh`,系统守护进程等)。记录了 exePath 的
            // 条目必须二次确认 PID 当前的 exe 路径跟启动时一致才发信号。
            if let expectedPath = entry.exePath {
                let currentPath = Self.executablePath(for: entry.pid)
                if currentPath != expectedPath {
                    // PID recycled — 跳过,killed 不计数,留给下次自然清理
                    continue
                }
            }
            // 注:旧 JSON 条目 exePath == nil 时不做 ownership 校验,只查 liveness。
            // 这是过渡期行为 — 一次启动后所有 record() 都会带上 exePath。

            _ = kill(entry.pid, SIGTERM)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if isAlive(pid: entry.pid) {
                _ = kill(entry.pid, SIGKILL)
            }
            killed.append((entry.profileID, entry.pid))
        }

        if !killed.isEmpty {
            entries = []
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

    /// 用 `proc_pidpath` 读 PID 当前的可执行文件路径,用于 ownership 校验。
    /// 进程已死 / 权限不够时返回 nil — 让 sweep 当作"无法校验"处理。
    private static func executablePath(for pid: Int32) -> String? {
        let bufferSize = 4096
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let result = proc_pidpath(pid_t(pid), &buffer, UInt32(bufferSize))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    private func persist() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? await store.write(data, to: fileURL)
    }
}
import Foundation
import Darwin

/// ManagedPID 应用层服务 — 在 `ManagedPIDDAO` 之上封装
/// (1) 启动时记录当前 SSH 子进程 PID
/// (2) 进程退出时清掉记录
/// (3) App 重启后 sweep 上一会话残留的孤儿进程
///
/// 与既有 `ManagedPIDStore` 的区别:
/// - `ManagedPIDStore` 是 actor + 直接耦合进程 sweep 行为(发 SIGTERM/SIGKILL),
///   是 Domain 服务层。
/// - `ManagedPIDServiceImpl` 把 sweep 行为做成 `@Sendable (Int32) -> String?` /
///   `@Sendable (Int32) -> Void` 注入 — 测试里可以用 fake
///   `proc_pidpath` / `kill`,不真发信号、不真访问 OS。
///
/// DAO 与 Service 并存:
/// - DAO 永远只 CRUD 持久化数据(任务 3 引入)。
/// - Service 在 DAO 之上提供业务用例(sweep 行为),能被 protocol-mock 测试。
///
/// 跟 App 重启相关的"读 + sweep"全在 service 这一层 — store 那条路径
/// 由 `ManagedPIDStore.sweep()` 继续保留,直到 Task 7 删除 store。
public protocol ManagedPIDService: Sendable {
    /// 记录一条新启动的 SSH 子进程 — 下次 App 启动 sweep 时按这个列表判定。
    /// 用 `profileID` + `pid` + `exePath` 三元组定位,SIGKILL 前会校验 exe 路径
    /// 跟启动时一致才发信号(防 PID recycle 误杀)。
    func track(pid: Int32, exePath: String, profileID: UUID) async throws

    /// 移除一条记录(进程已正常退出 / App willTerminate 后 sweep 完成)。
    func clear(pid: Int32) async throws

    /// App 启动时调用 — 遍历 DAO 里所有 PID,杀掉那些已死的、不再 listen
    /// ssh 进程的孤儿。返回被杀掉的 PID 数量。
    func sweepOrphans() async throws -> Int
}

/// 实际实现 — actor。`procPidPath` 与 `kill` 默认调用 `proc_pidpath` / `kill`，
/// 但生产 init 可显式注入 fake 用于测试。
public actor ManagedPIDServiceImpl: ManagedPIDService {

    private let dao: ManagedPIDDAO
    private let procPidPath: @Sendable (Int32) async -> String?
    private let kill: @Sendable (Int32) async -> Void

    public init(
        dao: ManagedPIDDAO,
        procPidPath: @escaping @Sendable (Int32) async -> String? = ManagedPIDServiceImpl.defaultProcPidPath,
        kill: @escaping @Sendable (Int32) async -> Void = ManagedPIDServiceImpl.defaultKill
    ) {
        self.dao = dao
        self.procPidPath = procPidPath
        self.kill = kill
    }

    public func track(pid: Int32, exePath: String, profileID: UUID) async throws {
        try await dao.upsert(ManagedPID(
            profileID: profileID,
            pid: pid,
            startedAt: Date(),
            exePath: exePath
        ))
    }

    public func clear(pid: Int32) async throws {
        try await dao.delete(pid: pid)
    }

    public func sweepOrphans() async throws -> Int {
        let entries = try await dao.loadAll()
        var killed = 0
        for entry in entries {
            // proc_pidpath 返回 nil = 进程已死(或者权限不足)。
            // 这两类都跳过 — 已死的本来 sweep 就不会发信号,
            // 权限不足留给 OS 自行清理。
            guard await procPidPath(entry.pid) == nil else { continue }
            await kill(entry.pid)
            try await dao.delete(pid: entry.pid)
            killed += 1
        }
        return killed
    }

    // MARK: - Defaults

    /// 默认 `proc_pidpath` 调用 — 进程不存在时返回 nil。
    public static let defaultProcPidPath: @Sendable (Int32) async -> String? = { pid in
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let ret = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return ret > 0 ? String(cString: buffer) : nil
    }

    /// 默认 SIGKILL 实际发信号 — 用负号 PID 把整个 process group 都杀掉。
    public static let defaultKill: @Sendable (Int32) async -> Void = { pid in
        _ = Darwin.kill(-pid, SIGKILL)
    }
}

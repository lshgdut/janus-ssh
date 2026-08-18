import Foundation

/// Profile 持久化协议 — 抽象层让未来可以切换到 SQLite 等后端
protocol ProfileRepository: Sendable {
    /// 从磁盘加载所有 profile
    /// - Throws: `RepositoryError.fileNotFound` 当文件不存在
    func load() async throws -> [Profile]

    /// 保存 profiles 到磁盘(覆盖式)
    /// 内部走 AtomicFileStore,失败时不会留下损坏文件
    func save(_ profiles: [Profile]) async throws

    /// 列出所有备份文件(按时间倒序,最新的在前)
    func listBackups() async throws -> [URL]

    /// 从指定备份恢复 — 备份成为新的主文件
    func restore(from backup: URL) async throws

    /// 从外部文件导入
    func importFrom(_ url: URL) async throws -> [Profile]
}
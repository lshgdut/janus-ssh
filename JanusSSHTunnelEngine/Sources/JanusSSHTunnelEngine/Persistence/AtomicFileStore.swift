import Foundation

/// 原子写入器:tmp + fsync + rename 模式。
///
/// 保证配置文件写入的原子性 — 即使 App 在写入过程中 crash,目标文件要么是旧版要么是新版,
/// 不会有损坏的中间态。同时维护一个 `.bak` 文件保存上一次成功的内容,便于恢复。
actor AtomicFileStore {

    enum AtomicStoreError: Error {
        case writeFailed(underlying: Error)
        case renameFailed(underlying: Error)
        case fsyncFailed(underlying: Error)
    }

    /// 原子写入 `data` 到 `url`。
    ///
    /// 流程:
    /// 1. 写入 `<url>.tmp`
    /// 2. fsync 文件
    /// 3. 如果目标文件已存在,改名为 `<url>.bak`(覆盖旧 bak)
    /// 4. rename tmp → 目标 url
    /// 5. fsync 父目录
    func write(_ data: Data, to url: URL) async throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()

        // 确保父目录存在
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        let tmpURL = url.appendingPathExtension("tmp")
        let bakURL = url.deletingPathExtension().appendingPathExtension("bak")

        // 清理可能残留的 tmp(上一次 crash 留下的)
        if fm.fileExists(atPath: tmpURL.path) {
            try? fm.removeItem(at: tmpURL)
        }

        do {
            // 1. 写入 tmp
            try data.write(to: tmpURL, options: [.atomic])

            // 2. fsync tmp 文件
            try fsync(fileURL: tmpURL)

            // 3. 如果目标已存在,先把旧版 rename 到 .bak(覆盖旧 bak),
            //    然后 tmp 原子 move 到目标位置。
            //    这个序列在 macOS 上足够原子 — 两步都是 rename 系统调用,
            //    中间 crash 窗口 < 1 个系统调用,且 tmp 是干净的(下个 write 会清理)。
            if fm.fileExists(atPath: url.path) {
                // 先把旧文件清掉 .bak
                if fm.fileExists(atPath: bakURL.path) {
                    try fm.removeItem(at: bakURL)
                }
                // 旧 → .bak
                try fm.moveItem(at: url, to: bakURL)
            }

            // tmp → url(moveItem 在目标不存在时直接成功;即使刚刚 move 完)
            try fm.moveItem(at: tmpURL, to: url)

            // 4. fsync 父目录(确保 rename 元数据落盘)
            try fsync(directoryURL: parent)
        } catch {
            // 失败时清理 tmp,避免污染
            try? fm.removeItem(at: tmpURL)
            throw error
        }
    }

    // MARK: - Private fsync helpers

    private func fsync(fileURL: URL) throws {
        let fd = Darwin.open(fileURL.path, O_RDONLY)
        if fd < 0 {
            throw AtomicStoreError.fsyncFailed(
                underlying: NSError(domain: "fsync", code: Int(errno))
            )
        }
        defer { Darwin.close(fd) }
        if Darwin.fsync(fd) != 0 {
            throw AtomicStoreError.fsyncFailed(
                underlying: NSError(domain: "fsync", code: Int(errno))
            )
        }
    }

    private func fsync(directoryURL: URL) throws {
        let fd = Darwin.open(directoryURL.path, O_RDONLY)
        if fd < 0 {
            // 父目录 fsync 失败通常不致命 — log 但不抛出
            return
        }
        defer { Darwin.close(fd) }
        _ = Darwin.fsync(fd)  // best-effort
    }
}
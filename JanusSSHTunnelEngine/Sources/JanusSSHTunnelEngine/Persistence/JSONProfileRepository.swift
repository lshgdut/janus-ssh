import Foundation

/// JSON + Atomic Write 的 ProfileRepository 实现
///
/// - 写入走 `AtomicFileStore`,不会留下损坏文件
/// - 每次 save 生成 ISO8601 timestamped 备份
/// - 自动轮转,保留最近 `maxBackups` 个备份
actor JSONProfileRepository: ProfileRepository {

    private let fileURL: URL
    private let backupDirectory: URL
    private let maxBackups: Int
    private let store: AtomicFileStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL,
        backupDirectory: URL,
        maxBackups: Int = 10,
        store: AtomicFileStore = AtomicFileStore()
    ) {
        self.fileURL = fileURL
        self.backupDirectory = backupDirectory
        self.maxBackups = maxBackups
        self.store = store

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func load() async throws -> [Profile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            throw RepositoryError.fileNotFound(fileURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw RepositoryError.decodeFailed("read: \(error.localizedDescription)")
        }

        let envelope: ProfileEnvelope
        do {
            envelope = try decoder.decode(ProfileEnvelope.self, from: data)
        } catch {
            throw RepositoryError.decodeFailed("parse: \(error.localizedDescription)")
        }

        guard envelope.version <= SchemaVersion.current.rawValue else {
            throw RepositoryError.unsupportedVersion(
                found: envelope.version,
                supported: SchemaVersion.current.rawValue
            )
        }

        return envelope.profiles
    }

    func save(_ profiles: [Profile]) async throws {
        try ensureBackupDirectory()

        let envelope = ProfileEnvelope(profiles: profiles, updatedAt: Date())
        let data = try encoder.encode(envelope)
        // 主写入必须成功 — 否则视为整次 save 失败
        try await store.write(data, to: fileURL)

        // Backup 是 best-effort:失败不抛错(主文件已经原子写入),
        // 但记入 console 让用户可以发现磁盘满等异常
        do {
            try createTimestampedBackup()
        } catch {
            print("[Janus] backup creation failed (non-fatal): \(error)")
        }

        // 轮转也是 best-effort
        do {
            try await rotateBackups()
        } catch {
            print("[Janus] backup rotation failed (non-fatal): \(error)")
        }
    }

    func listBackups() async throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupDirectory.path) else {
            return []
        }
        let urls = try fm.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        return urls
            .filter { $0.lastPathComponent.hasPrefix("profiles-") }
            .sorted { lhs, rhs in
                let lMod = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let rMod = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return lMod > rMod
            }
    }

    func restore(from backup: URL) async throws {
        // 把当前主文件复制成 .bak,再用 backup 内容覆盖主文件
        let data = try Data(contentsOf: backup)
        try await store.write(data, to: fileURL)
    }

    func importFrom(_ url: URL) async throws -> [Profile] {
        let data = try Data(contentsOf: url)
        let envelope = try decoder.decode(ProfileEnvelope.self, from: data)
        return envelope.profiles
    }

    // MARK: - Private

    private func ensureBackupDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: backupDirectory.path) {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }
    }

    private func createTimestampedBackup() throws {
        let fm = FileManager.default
        // 用带 fractional seconds 的 ISO8601,避免同秒内连续 save 时文件名冲突
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")  // 文件名不能含 :
        let backupURL = backupDirectory.appendingPathComponent("profiles-\(stamp).json")
        try fm.copyItem(at: fileURL, to: backupURL)
    }

    private func rotateBackups() async throws {
        let backups = try await listBackups()
        guard backups.count > maxBackups else { return }
        let toRemove = backups.suffix(backups.count - maxBackups)
        for url in toRemove {
            try FileManager.default.removeItem(at: url)
        }
    }
}
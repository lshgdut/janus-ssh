import Foundation

/// Per-profile 内存日志存储 — UI 通过 `subscribe` 拿实时流。
/// 环形缓冲:每 Profile 最多 1000 条,超出后丢弃最旧。
actor TunnelLogStore {

    struct Entry: Sendable, Identifiable {
        let id: UUID
        let timestamp: Date
        let kind: Kind
        let level: Level
        let message: String

        enum Kind: String, Sendable { case app, stdout, stderr }
        enum Level: String, Sendable { case info, warn, error }
    }

    static let bufferCapacity = 1000

    private var buffers: [UUID: [Entry]] = [:]
    private var continuations: [UUID: [UUID: AsyncStream<Entry>.Continuation]] = [:]

    func append(profileID: UUID, _ entry: Entry) {
        var buf = buffers[profileID, default: []]
        buf.append(entry)
        if buf.count > Self.bufferCapacity {
            buf.removeFirst(buf.count - Self.bufferCapacity)
        }
        buffers[profileID] = buf

        // 通知订阅者
        if let subs = continuations[profileID] {
            for c in subs.values {
                c.yield(entry)
            }
        }
    }

    /// 便利方法:从 stderr/stdout 字节构造 entry
    func append(profileID: UUID, kind: Entry.Kind, message: String, level: Entry.Level = .info) {
        let entry = Entry(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            level: level,
            message: message
        )
        append(profileID: profileID, entry)
    }

    func snapshot(profileID: UUID) -> [Entry] {
        return buffers[profileID] ?? []
    }

    func subscribe(profileID: UUID) -> AsyncStream<Entry> {
        let id = UUID()
        return AsyncStream { continuation in
            var subs = continuations[profileID, default: [:]]
            subs[id] = continuation
            continuations[profileID] = subs

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                Task { await self.removeSub(profileID: profileID, subID: id) }
            }
        }
    }

    func clear(profileID: UUID) {
        buffers[profileID] = []
    }

    private func removeSub(profileID: UUID, subID: UUID) {
        guard var subs = continuations[profileID] else { return }
        subs.removeValue(forKey: subID)
        continuations[profileID] = subs
    }
}
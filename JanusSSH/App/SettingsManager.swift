import Foundation
import Observation
import JanusSSHTunnelEngine

/// 全局设置管理 — 单一可观察的 settings 对象
@MainActor
@Observable
final class SettingsManager {
    private let repository: SettingsRepository
    private(set) var state: AppSettings = .defaults

    init(repository: SettingsRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            state = try await repository.load()
        } catch {
            state = .defaults
        }
    }

    func update(_ mutation: (inout AppSettings) -> Void) async {
        // Diff-then-write:在 off-Observable 的本地副本上跑 mutation,
        // 仅当值真的变了才回写 state + 持久化。
        // 这就堵死了"MenuBarExtra(isInserted:) ↔ macOS NSStatusItem overflow"
        // 触发的 ~150 Hz setter 风暴 — 即便 setter 被连续调 N 次,
        // 只要值没变就不再触发 @Observable change、不再 spawn 写盘 Task,
        // 不再跑 JSON encode + fsync + rename。
        var newState = state
        mutation(&newState)
        guard newState != state else { return }
        state = newState
        try? await repository.save(state)
    }
}

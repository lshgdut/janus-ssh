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
        mutation(&state)
        try? await repository.save(state)
    }
}

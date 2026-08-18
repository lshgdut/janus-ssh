import Foundation
import Observation
import JanusSSHTunnelEngine

/// SSH Host 管理器 — 从 ssh config 发现 + 缓存
@MainActor
@Observable
final class SSHHostManager {
    let provider: SSHConfigProviding
    private(set) var hosts: [SSHHost] = []
    private(set) var lastError: String?
    private(set) var lastRefreshed: Date?

    init(provider: SSHConfigProviding, defaultConfigPath: String) {
        self.provider = provider
    }

    func refresh() async {
        do {
            hosts = try await provider.discoverHosts()
            lastError = nil
            lastRefreshed = Date()
        } catch {
            hosts = []
            lastError = error.localizedDescription
        }
    }

    func test(alias: String) async -> ConnectionTestResult {
        do {
            return try await provider.testConnection(alias: alias)
        } catch {
            return .unreachable(reason: error.localizedDescription)
        }
    }
}
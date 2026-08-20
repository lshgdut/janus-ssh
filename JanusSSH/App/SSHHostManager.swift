import Foundation
import Observation
import JanusSSHTunnelEngine

/// SSH Host 管理器 — 从 ssh config 发现 + 缓存 + 测试状态跟踪
@MainActor
@Observable
final class SSHHostManager {
    let provider: SSHConfigProviding
    private(set) var hosts: [SSHHost] = []
    private(set) var lastError: String?
    private(set) var lastRefreshed: Date?
    private(set) var testResults: [String: TestResult] = [:]

    struct TestResult: Equatable {
        let outcome: ConnectionTestResult
        let testedAt: Date
    }

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

    /// 同步测试 + 缓存结果
    @discardableResult
    func test(alias: String) async -> ConnectionTestResult {
        do {
            let result = try await provider.testConnection(alias: alias)
            testResults[alias] = TestResult(outcome: result, testedAt: Date())
            return result
        } catch {
            let result = ConnectionTestResult.unreachable(reason: error.localizedDescription)
            testResults[alias] = TestResult(outcome: result, testedAt: Date())
            return result
        }
    }

    func result(for alias: String) -> TestResult? {
        testResults[alias]
    }
}
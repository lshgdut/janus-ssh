import XCTest
@testable import JanusSSHTunnelEngine

/// SSHConfigManager(应用层)测试 — 用 `FakeSSHConfigProviding` 替换真实
/// `SSHConfigService`,验证 refresh 缓存 / lastError / lastRefreshed /
/// testResults 语义。
@MainActor
final class SSHConfigManagerTests: XCTestCase {

    // MARK: - refresh

    func test_refresh_populates_hosts_and_metadata_on_success() async {
        let provider = FakeSSHConfigProviding()
        await provider.setHosts([
            makeHost(alias: "h1"),
            makeHost(alias: "h2"),
        ])
        let mgr = SSHConfigManagerImpl(provider: provider)

        XCTAssertTrue(mgr.hosts.isEmpty)
        XCTAssertNil(mgr.lastError)
        XCTAssertNil(mgr.lastRefreshed)

        await mgr.refresh()

        XCTAssertEqual(mgr.hosts.count, 2)
        XCTAssertEqual(mgr.hosts.first?.alias, "h1")
        XCTAssertEqual(mgr.hosts.last?.alias, "h2")
        XCTAssertNil(mgr.lastError)
        XCTAssertNotNil(mgr.lastRefreshed)
    }

    func test_refresh_records_error_on_failure() async {
        let provider = FakeSSHConfigProviding()
        await provider.setError(TestError.bang)
        let mgr = SSHConfigManagerImpl(provider: provider)

        await mgr.refresh()

        XCTAssertTrue(mgr.hosts.isEmpty)
        XCTAssertNotNil(mgr.lastError)
        XCTAssertNil(mgr.lastRefreshed)
    }

    func test_refresh_clears_error_after_recovery() async {
        let provider = FakeSSHConfigProviding()
        await provider.setError(TestError.bang)
        let mgr = SSHConfigManagerImpl(provider: provider)

        await mgr.refresh()
        XCTAssertNotNil(mgr.lastError)

        await provider.setError(nil)
        await provider.setHosts([makeHost(alias: "h1")])

        await mgr.refresh()
        XCTAssertNil(mgr.lastError)
        XCTAssertEqual(mgr.hosts.count, 1)
        XCTAssertNotNil(mgr.lastRefreshed)
    }

    // MARK: - test

    func test_test_caches_reachable_result() async {
        let provider = FakeSSHConfigProviding()
        await provider.setTestResult(.reachable(latencyMs: 42))
        let mgr = SSHConfigManagerImpl(provider: provider)

        let outcome = await mgr.test(alias: "h1")

        XCTAssertEqual(outcome, .reachable(latencyMs: 42))
        let cached = mgr.result(for: "h1")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.outcome, .reachable(latencyMs: 42))
        XCTAssertNotNil(cached?.testedAt)
    }

    func test_test_caches_unreachable_when_provider_throws() async {
        let provider = FakeSSHConfigProviding()
        await provider.setTestError(TestError.bang)
        let mgr = SSHConfigManagerImpl(provider: provider)

        let outcome = await mgr.test(alias: "h1")

        guard case .unreachable = outcome else {
            XCTFail("expected .unreachable, got \(outcome)")
            return
        }
        let cached = mgr.result(for: "h1")
        XCTAssertNotNil(cached)
        guard case .unreachable = cached?.outcome else {
            XCTFail("cached outcome should be .unreachable")
            return
        }
    }

    func test_test_overwrites_prior_result_for_same_alias() async {
        let provider = FakeSSHConfigProviding()
        let mgr = SSHConfigManagerImpl(provider: provider)

        await provider.setTestResult(.reachable(latencyMs: 10))
        _ = await mgr.test(alias: "h1")
        let firstTimestamp = mgr.result(for: "h1")?.testedAt

        try? await Task.sleep(nanoseconds: 10_000_000)

        await provider.setTestResult(.unreachable(reason: "boom"))
        let outcome = await mgr.test(alias: "h1")

        XCTAssertEqual(outcome, .unreachable(reason: "boom"))
        let cached = mgr.result(for: "h1")
        XCTAssertEqual(cached?.outcome, .unreachable(reason: "boom"))
        XCTAssertNotNil(cached?.testedAt)
        XCTAssertNotEqual(cached?.testedAt, firstTimestamp)
    }

    func test_result_returns_nil_for_unknown_alias() async {
        let provider = FakeSSHConfigProviding()
        let mgr = SSHConfigManagerImpl(provider: provider)

        XCTAssertNil(mgr.result(for: "nope"))
    }

    // MARK: - Helpers

    private func makeHost(alias: String) -> SSHHost {
        SSHHost(
            alias: alias,
            user: nil,
            hostname: alias + ".example.com",
            port: nil,
            identityFiles: [],
            proxyJump: nil,
            forwardAgent: nil,
            serverAliveInterval: nil
        )
    }
}

/// actor 化的 fake — `SSHConfigProviding` 跨 actor 边界,需要 Sendable 安全。
private actor FakeSSHConfigProviding: SSHConfigProviding {
    private var hosts: [SSHHost] = []
    private var error: Error?
    private var testResult: ConnectionTestResult = .reachable(latencyMs: 0)
    private var testError: Error?

    func setHosts(_ hosts: [SSHHost]) { self.hosts = hosts }
    func setError(_ error: Error?) { self.error = error }
    func setTestResult(_ result: ConnectionTestResult) { self.testResult = result }
    func setTestError(_ error: Error?) { self.testError = error }

    func discoverHosts() async throws -> [SSHHost] {
        if let error { throw error }
        return hosts
    }

    func resolve(host: String) async throws -> ResolvedHostConfig {
        ResolvedHostConfig(
            alias: host,
            user: nil,
            hostname: host,
            port: nil,
            identityFiles: [],
            proxyJump: nil,
            proxyCommand: nil
        )
    }

    func testConnection(alias: String) async throws -> ConnectionTestResult {
        if let testError { throw testError }
        return testResult
    }
}

private enum TestError: Error, Equatable {
    case bang
}
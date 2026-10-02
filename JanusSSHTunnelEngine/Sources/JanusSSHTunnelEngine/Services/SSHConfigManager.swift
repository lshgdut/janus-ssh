import Foundation
import Observation

/// SSH Host 管理器(应用层) — 缓存 `SSHConfigProviding` 的发现结果 + 跟踪测试状态。
///
/// 设计要点(与既有 `JanusSSH/App/SSHHostManager.swift` 对齐):
/// - `@MainActor @Observable`:UI 通过 `@Bindable` 或直接属性访问观察 `hosts`、
///   `testResults`,任何修改都会自动触发 SwiftUI 重新渲染。
/// - `@MainActor` 保证 `hosts` / `testResults` 数组与其他 ViewModel 的并发读写都在
///   同一个隔离域里,避免 Swift 6 strict concurrency 下的数据竞争。
/// - `provider` 是协议抽象 `SSHConfigProviding`,测试里可注入 fake;生产用
///   既有 `SSHConfigService`(文件解析 + ssh -G)。
/// - TestResult 缓存按 alias 索引,UI 通过 `result(for:)` 查询最近一次测试结果。
///
/// 与既有 `SSHHostManager` 的关系:
/// - `SSHHostManager`(App 层)在 Task 7 删除 — AppContainer 直接持有
///   `services.sshConfigManager`。
/// - 本文件不依赖 SwiftUI,可在 `JanusSSHTunnelEngine` 单测里直接构造。
///
/// 命名说明:`SSHConfigManager` 与既有具体类 `SSHConfigService`(`SSHConfigProviding`
/// 的实现)不冲突 — 前者是 application service,后者是 SSH config 文件读取 + ssh -G
/// 的低层 provider。Task 7 把 AppContainer 的 `sshHostManager` 切到
/// `services.sshConfigManager` 后,这个分层完全可解耦。
@MainActor
public protocol SSHConfigManager: AnyObject, Sendable {
    /// 当前已发现的 host 缓存。UI 直接 bindable 观察。
    var hosts: [SSHHost] { get }
    /// 最近一次 refresh 抛出的异常的本地化描述;成功时为 nil。
    var lastError: String? { get }
    /// 最近一次成功 refresh 的时间戳;首次未刷新时为 nil。
    var lastRefreshed: Date? { get }
    /// 测试结果缓存(key = host alias)。
    var testResults: [String: SSHConfigManagerImpl.TestResult] { get }

    /// 触发一次 host 发现:从 `provider` 拉一次,刷新 `hosts` / `lastError` /
    /// `lastRefreshed`。
    func refresh() async

    /// 测试某个 host 是否可达,并把结果写入 `testResults` 缓存。
    /// 返回实际测试结果(成功 / 失败 / 超时)。
    @discardableResult
    func test(alias: String) async -> ConnectionTestResult

    /// 同步查询缓存里某个 host 的最近一次测试结果。
    func result(for alias: String) -> SSHConfigManagerImpl.TestResult?
}

@MainActor
@Observable
public final class SSHConfigManagerImpl: SSHConfigManager {

    /// 单条测试结果 — 与既有 `SSHHostManager.TestResult` 等价(从 App 层平移)。
    public struct TestResult: Equatable, Sendable {
        public let outcome: ConnectionTestResult
        public let testedAt: Date

        public init(outcome: ConnectionTestResult, testedAt: Date) {
            self.outcome = outcome
            self.testedAt = testedAt
        }
    }

    public private(set) var hosts: [SSHHost] = []
    public private(set) var lastError: String?
    public private(set) var lastRefreshed: Date?
    public private(set) var testResults: [String: TestResult] = [:]

    private let provider: SSHConfigProviding

    public init(provider: SSHConfigProviding) {
        self.provider = provider
    }

    public func refresh() async {
        do {
            hosts = try await provider.discoverHosts()
            lastError = nil
            lastRefreshed = Date()
        } catch {
            hosts = []
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    public func test(alias: String) async -> ConnectionTestResult {
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

    public func result(for alias: String) -> TestResult? {
        testResults[alias]
    }
}
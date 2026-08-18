import XCTest
@testable import JanusSSHTunnelEngine

/// PortChecker 在启动 Profile 前检查本地端口是否空闲。
/// 实现用 NWConnection 做 TCP connect — 失败说明端口无人 LISTEN,
/// 但不能保证 bind 一定成功(仍依赖 ssh -L 的 ExitOnForwardFailure 兜底)。
final class PortCheckerTests: XCTestCase {

    func test_port_checker_protocol_can_be_mocked() async {
        // Protocol 抽象层 — 验证 mock 能正常工作
        let mock = MockPortChecker()
        mock.setAvailable(true, for: 15432)

        let port = 15432
        let available = await mock.isPortAvailable(host: "127.0.0.1", port: UInt16(port))
        XCTAssertTrue(available)
    }

    func test_mock_reports_unavailable_when_set() async {
        let mock = MockPortChecker()
        mock.setAvailable(false, for: 8080)

        let available = await mock.isPortAvailable(host: "127.0.0.1", port: 8080)
        XCTAssertFalse(available)
    }

    func test_default_mock_treats_all_ports_available() async {
        let mock = MockPortChecker()
        let a = await mock.isPortAvailable(host: "127.0.0.1", port: 12345)
        let b = await mock.isPortAvailable(host: "127.0.0.1", port: 67890)
        XCTAssertTrue(a)
        XCTAssertTrue(b)
    }
}

/// 测试用 mock PortChecker
final class MockPortChecker: PortChecking, @unchecked Sendable {
    private var map: [UInt16: Bool] = [:]
    private let lock = NSLock()

    func setAvailable(_ available: Bool, for port: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        map[port] = available
    }

    func isPortAvailable(host: String, port: UInt16) async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return map[port] ?? true  // 默认可用
    }
}
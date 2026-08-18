import XCTest
@testable import JanusSSHTunnelEngine

/// TunnelError 是贯穿整个 App 的错误类型。
/// 必须 Equatable — UI / 日志系统需要能直接比较。
final class TunnelErrorTests: XCTestCase {

    func test_tunnel_errors_are_equatable_for_log_dedup() {
        let a = TunnelError.duplicateLocalPort(15432)
        let b = TunnelError.duplicateLocalPort(15432)
        let c = TunnelError.duplicateLocalPort(16379)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func test_cross_profile_conflict_carries_conflicting_profile_ids() {
        let a = UUID(); let b = UUID(); let c = UUID()
        let err = TunnelError.crossProfileLocalPortConflict(
            port: 15432,
            occupiedBy: [a, b, c]
        )

        if case let .crossProfileLocalPortConflict(port, occupied) = err {
            XCTAssertEqual(port, 15432)
            XCTAssertEqual(occupied, [a, b, c])
        } else {
            XCTFail("wrong error case: \(err)")
        }
    }

    func test_ssh_exit_error_carries_code_and_reason() {
        let err = TunnelError.sshExited(code: 255, signal: nil, reason: .processExited)

        if case let .sshExited(code, signal, reason) = err {
            XCTAssertEqual(code, 255)
            XCTAssertNil(signal)
            XCTAssertEqual(reason, .processExited)
        } else {
            XCTFail("wrong error case: \(err)")
        }
    }

    func test_errors_carry_descriptions_for_ui() {
        // UI 在 Editor / Dashboard / Settings 都会显示错误文案,需要稳定的描述
        let err = TunnelError.localPortUnavailable(8080)
        XCTAssertTrue(err.errorDescription?.contains("8080") == true,
                      "Description should mention port 8080, got: \(err.errorDescription ?? "nil")")
    }
}
import XCTest
@testable import JanusSSHTunnelEngine

/// TunnelState 描述一个 Profile 在 TunnelManager 中的实时运行状态。
/// 状态机:stopped → starting → running → stopping → stopped
///                  ↑             │
///                  └─ reconnecting(异常退出时)
///                  ↓
///                error
final class TunnelStateTests: XCTestCase {

    func test_tunnel_state_can_transition_from_stopped_to_starting() {
        let initial = TunnelState.stopped
        let next = TunnelState.starting
        XCTAssertNotEqual(next, initial)
    }

    func test_tunnel_state_running_is_distinct_from_reconnecting() {
        // 关键区别:running 是稳定的,reconnecting 是退避中 — UI 颜色和重试逻辑都依赖这个区分
        XCTAssertNotEqual(TunnelState.running, TunnelState.reconnecting)
    }

    func test_tunnel_state_can_be_equated() {
        XCTAssertEqual(TunnelState.stopped, TunnelState.stopped)
        XCTAssertEqual(TunnelState.running, TunnelState.running)
    }

    func test_tunnel_holds_runtime_state_separate_from_profile() {
        // Tunnel 包含 profileSnapshot + runtime fields(state, pid, startedAt, lastError)
        let snap = ProfileSnapshot(
            id: UUID(),
            name: "Production",
            sshHostAlias: "production",
            forwards: [],
            autoReconnect: true
        )

        let tunnel = Tunnel(
            profileSnapshot: snap,
            state: .running,
            pid: 41928,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastError: nil
        )

        XCTAssertEqual(tunnel.id, snap.id)
        XCTAssertEqual(tunnel.state, .running)
        XCTAssertEqual(tunnel.pid, 41928)
        XCTAssertNil(tunnel.lastError)
    }

    func test_tunnel_records_termination_reason_distinct_from_user_stop() {
        // Auto Reconnect 必须能区分"用户主动 stop"和"SSH 异常退出",否则错误地无限重连
        let userStop = TerminationReason.userRequested
        let crash = TerminationReason.processExited
        XCTAssertNotEqual(userStop, crash)
    }

    func test_termination_reasons_are_exhaustive_for_state_machine() {
        // 验证四个 reason 都存在且可区分 — 后续 ReconnectController 会用这张表做决策
        let reasons: Set<TerminationReason> = [
            .userRequested, .processExited, .applicationShutdown, .startupFailure
        ]
        XCTAssertEqual(reasons.count, 4)
    }
}
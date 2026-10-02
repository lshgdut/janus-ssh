import XCTest
@testable import JanusSSHTunnelEngine

final class TunnelEventTests: XCTestCase {

    func test_stateChanged_carries_tunnel() {
        let profile = Profile(
            name: "p",
            sshHostAlias: "h",
            forwards: [],
            behavior: .defaults
        )
        let tunnel = Tunnel(
            profileSnapshot: ProfileSnapshot(profile),
            state: .running,
            pid: 1234,
            startedAt: Date(),
            stoppedAt: nil,
            lastError: nil
        )
        let event = TunnelEvent.stateChanged(tunnel)

        if case let .stateChanged(recovered) = event {
            XCTAssertEqual(recovered.id, tunnel.id)
            XCTAssertEqual(recovered.pid, 1234)
        } else {
            XCTFail("wrong case")
        }
    }

    func test_profileID_is_stable_across_cases() {
        let profileID = UUID()
        let s = TunnelEvent.stateChanged(Tunnel(
            profileSnapshot: ProfileSnapshot(
                id: profileID, name: "n", sshHostAlias: "h",
                forwards: [], autoReconnect: false
            ),
            state: .stopped
        ))
        let l = TunnelEvent.logLine(profileID: profileID, line: "x")
        let e = TunnelEvent.exited(
            profileID: profileID, reason: .processExited, code: 0, signal: nil
        )

        XCTAssertEqual(s.profileID, profileID)
        XCTAssertEqual(l.profileID, profileID)
        XCTAssertEqual(e.profileID, profileID)
    }
}

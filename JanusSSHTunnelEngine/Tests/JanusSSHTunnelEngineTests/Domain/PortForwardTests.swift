import XCTest
@testable import JanusSSHTunnelEngine

/// PortForward 对应原型 Editor 中的 Forwards 表格的一行:
/// LocalHost:LocalPort → RemoteHost:RemotePort,可选 label(postgres/redis/http)。
final class PortForwardTests: XCTestCase {

    func test_portforward_local_endpoint_is_127_0_0_1_by_convention() {
        let f = PortForward(
            localHost: "127.0.0.1",
            localPort: 15432,
            remoteHost: "10.20.0.15",
            remotePort: 5432,
            label: "postgres"
        )
        XCTAssertEqual(f.localEndpoint, "127.0.0.1:15432")
    }

    func test_portforward_ssh_argument_form_is_L_spec() {
        // ssh -L 的参数形式:localHost:localPort:remoteHost:remotePort
        let f = PortForward(
            localHost: "127.0.0.1",
            localPort: 15432,
            remoteHost: "10.20.0.15",
            remotePort: 5432,
            label: nil
        )
        XCTAssertEqual(f.sshArgument, "127.0.0.1:15432:10.20.0.15:5432")
    }

    func test_portforward_label_is_optional() {
        let unlabeled = PortForward(
            localHost: "127.0.0.1", localPort: 9000,
            remoteHost: "10.0.0.1", remotePort: 9090, label: nil
        )
        let labeled = PortForward(
            localHost: "127.0.0.1", localPort: 9000,
            remoteHost: "10.0.0.1", remotePort: 9090, label: "metrics"
        )

        XCTAssertNil(unlabeled.label)
        XCTAssertEqual(labeled.label, "metrics")
    }

    func test_portforward_roundtrips_through_codable() throws {
        let original = PortForward(
            localHost: "127.0.0.1", localPort: 15432,
            remoteHost: "10.20.0.15", remotePort: 5432, label: "postgres"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PortForward.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_portforward_identifiable_by_id() {
        let a = PortForward(localHost: "127.0.0.1", localPort: 1,
                            remoteHost: "r", remotePort: 1, label: nil)
        let b = PortForward(localHost: "127.0.0.1", localPort: 1,
                            remoteHost: "r", remotePort: 1, label: nil)
        XCTAssertNotEqual(a.id, b.id)
    }
}
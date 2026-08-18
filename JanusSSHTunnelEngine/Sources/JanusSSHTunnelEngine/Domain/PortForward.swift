import Foundation

/// PortForward 对应 `-L` 参数的一行。
///
/// ssh -L 的参数形式: `localHost:localPort:remoteHost:remotePort`
struct PortForward: Codable, Identifiable, Hashable, Sendable {
    let id: UUID

    var localHost: String
    var localPort: UInt16

    var remoteHost: String
    var remotePort: UInt16

    var label: String?

    init(
        id: UUID = UUID(),
        localHost: String,
        localPort: UInt16,
        remoteHost: String,
        remotePort: UInt16,
        label: String?
    ) {
        self.id = id
        self.localHost = localHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.label = label
    }

    /// `127.0.0.1:15432` 形式,用于 UI 显示
    var localEndpoint: String {
        "\(localHost):\(localPort)"
    }

    /// ssh -L 参数形式: `127.0.0.1:15432:10.20.0.15:5432`
    var sshArgument: String {
        "\(localHost):\(localPort):\(remoteHost):\(remotePort)"
    }
}
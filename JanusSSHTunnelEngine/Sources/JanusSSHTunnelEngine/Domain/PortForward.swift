import Foundation

/// PortForward 对应 `-L` 参数的一行。
///
/// ssh -L 的参数形式: `localHost:localPort:remoteHost:remotePort`
public struct PortForward: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID

    public var localHost: String
    public var localPort: UInt16

    public var remoteHost: String
    public var remotePort: UInt16

    public var label: String?

    public init(
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
    public var localEndpoint: String {
        "\(localHost):\(localPort)"
    }

    /// ssh -L 参数形式: `127.0.0.1:15432:10.20.0.15:5432`
    public var sshArgument: String {
        "\(localHost):\(localPort):\(remoteHost):\(remotePort)"
    }
}
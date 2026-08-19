import Foundation

/// 从 ~/.ssh/config 解析出来的 host 信息(只读视图)
public struct SSHHost: Identifiable, Hashable, Sendable {
    public var id: String { alias }
    public let alias: String
    public let user: String?
    public let hostname: String?
    public let port: Int?
    public let identityFiles: [String]
    public let proxyJump: String?
    public let forwardAgent: Bool?
    public let serverAliveInterval: Int?
}

/// ssh -G 输出的完整配置(用于构造完整 SSH 命令)
public struct ResolvedHostConfig: Sendable, Equatable {
    public let alias: String
    public let user: String?
    public let hostname: String?
    public let port: Int?
    public let identityFiles: [String]
    public let proxyJump: String?
    public let proxyCommand: String?
}

public enum ConnectionTestResult: Sendable, Equatable {
    case reachable(latencyMs: Int)
    case unreachable(reason: String)
    case timeout
}
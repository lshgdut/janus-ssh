import Foundation

/// 从 ~/.ssh/config 解析出来的 host 信息(只读视图)
struct SSHHost: Identifiable, Hashable, Sendable {
    var id: String { alias }
    let alias: String
    let user: String?
    let hostname: String?
    let port: Int?
    let identityFiles: [String]
    let proxyJump: String?
    let forwardAgent: Bool?
    let serverAliveInterval: Int?
}

/// ssh -G 输出的完整配置(用于构造完整 SSH 命令)
struct ResolvedHostConfig: Sendable, Equatable {
    let alias: String
    let user: String?
    let hostname: String?
    let port: Int?
    let identityFiles: [String]
    let proxyJump: String?
    let proxyCommand: String?
}

enum ConnectionTestResult: Sendable, Equatable {
    case reachable(latencyMs: Int)
    case unreachable(reason: String)
    case timeout
}
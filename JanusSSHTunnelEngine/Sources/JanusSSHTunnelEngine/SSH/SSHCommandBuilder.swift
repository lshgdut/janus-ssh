import Foundation

/// SSH 命令构造错误
public enum SSHCommandBuilderError: Error, LocalizedError, Equatable {
    case noForwards
    case emptyForwardRow(index: Int)

    public var errorDescription: String? {
        switch self {
        case .noForwards:
            return "Profile has no port forwards; cannot start tunnel."
        case .emptyForwardRow(let index):
            return "Forward row \(index) is incomplete and was skipped."
        }
    }
}

/// 构造好的可执行命令 — 通过 argv 数组传给 Foundation.Process,不经过 shell
public struct SSHCommand: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]?
    public let workingDirectory: String?
}

/// SSH 命令构造器。
///
/// 关键不变性:
/// - 默认包含 `-N`(不打开远程 shell)
/// - 默认包含 `-T`(强制不分配 tty — GUI app 启动的子进程无 stdin tty,SSH 默认会告警并部分失败)
/// - 默认包含 `-o ExitOnForwardFailure=yes`(Janus 的核心安全网)
/// - 默认包含 `-o BatchMode=yes` + ServerAlive(避免卡在密码提示)
/// - 每个 PortForward 对应一个 `-L <localHost:localPort:remoteHost:remotePort>`
/// - sshHostAlias 作为最后一个位置参数
/// - 透传 SSH_AUTH_SOCK 等关键 env(GUI app 启动时常缺这些 env,SSH 无法连 agent)
public struct SSHCommandBuilder: Sendable {
    public init() {}

    /// 默认 ssh 二进制位置
    static let defaultSSHPath = URL(fileURLWithPath: "/usr/bin/ssh")

    /// Janus SSH 强制添加的安全 flag — 不可配置,不可关闭
    static let mandatoryFlags: [String] = [
        "-N",                                            // 不要 tty / 不要远程命令
        "-T",                                            // 强制不分配 remote tty(GUI 子进程无 stdin tty)
        "-o", "ExitOnForwardFailure=yes",                // 任一 forward 失败即退出
        "-o", "BatchMode=yes",                           // 不提示密码
        "-o", "StrictHostKeyChecking=accept-new",        // 首次连接自动接受
        "-o", "ServerAliveInterval=60",
        "-o", "ServerAliveCountMax=3"
    ]

    /// 透传给 SSH 子进程的环境变量
    /// GUI app 启动时 launchd env 是精简版,经常缺 SSH_AUTH_SOCK,
    /// 导致 SSH 无法跟 1Password / ssh-agent 通信而 auth 失败
    static let forwardedEnvKeys: [String] = [
        "SSH_AUTH_SOCK",     // ssh-agent / 1Password SSH agent socket
        "SSH_AGENT_PID",     // ssh-agent PID
        "HOME",              // 找 ~/.ssh
        "USER",              // ssh config 里 $user 展开
        "LOGNAME",           // 某些 SSH 拓展看这个
        "PATH",              // ProxyCommand 等可能需要
        "LANG", "LC_ALL",    // 错误信息编码
        "TMPDIR"             // SSH 内部临时文件
    ]

    public func build(profile: ProfileSnapshot) throws -> SSHCommand {
        guard !profile.forwards.isEmpty else {
            throw SSHCommandBuilderError.noForwards
        }

        var args: [String] = []
        args.append(contentsOf: Self.mandatoryFlags)

        // 跳过空行(localPort==0 或 remoteHost 空)
        var validCount = 0
        for forward in profile.forwards {
            guard forward.localPort != 0,
                  !forward.remoteHost.isEmpty,
                  forward.remotePort != 0 else {
                continue
            }
            args.append("-L")
            args.append(forward.sshArgument)
            validCount += 1
        }

        guard validCount > 0 else {
            throw SSHCommandBuilderError.noForwards
        }

        args.append(profile.sshHostAlias)

        return SSHCommand(
            executable: Self.defaultSSHPath,
            arguments: args,
            environment: Self.collectEnvironment(),
            workingDirectory: ProcessInfo.processInfo.environment["HOME"]
        )
    }

    /// 从当前进程(env)中收集需要透传给 SSH 子进程的变量
    static func collectEnvironment() -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        var result: [String: String] = [:]
        for key in forwardedEnvKeys {
            if let value = parent[key], !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }
}
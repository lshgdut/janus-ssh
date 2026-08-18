import Foundation

/// SSH 命令构造错误
enum SSHCommandBuilderError: Error, LocalizedError, Equatable {
    case noForwards
    case emptyForwardRow(index: Int)

    var errorDescription: String? {
        switch self {
        case .noForwards:
            return "Profile has no port forwards; cannot start tunnel."
        case .emptyForwardRow(let index):
            return "Forward row \(index) is incomplete and was skipped."
        }
    }
}

/// 构造好的可执行命令 — 通过 argv 数组传给 Foundation.Process,不经过 shell
struct SSHCommand: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]?
}

/// SSH 命令构造器。
///
/// 关键不变性:
/// - 默认包含 `-N`(不打开远程 shell)
/// - 默认包含 `-o ExitOnForwardFailure=yes`(Janus 的核心安全网)
/// - 默认包含 `-o BatchMode=yes` + ServerAlive(避免卡在密码提示)
/// - 每个 PortForward 对应一个 `-L <localHost:localPort:remoteHost:remotePort>`
/// - sshHostAlias 作为最后一个位置参数
struct SSHCommandBuilder: Sendable {

    /// 默认 ssh 二进制位置
    static let defaultSSHPath = URL(fileURLWithPath: "/usr/bin/ssh")

    /// Janus SSH 强制添加的安全 flag — 不可配置,不可关闭
    static let mandatoryFlags: [String] = [
        "-N",                                            // 不要 tty
        "-o", "ExitOnForwardFailure=yes",                // 任一 forward 失败即退出
        "-o", "BatchMode=yes",                           // 不提示密码
        "-o", "StrictHostKeyChecking=accept-new",        // 首次连接自动接受
        "-o", "ServerAliveInterval=60",
        "-o", "ServerAliveCountMax=3"
    ]

    func build(profile: ProfileSnapshot) throws -> SSHCommand {
        guard !profile.forwards.isEmpty else {
            throw SSHCommandBuilderError.noForwards
        }

        var args: [String] = []
        args.append(contentsOf: Self.mandatoryFlags)

        // 跳过空行(localPort==0 或 remoteHost 空)
        var validCount = 0
        for (idx, forward) in profile.forwards.enumerated() {
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
            environment: nil
        )
    }
}
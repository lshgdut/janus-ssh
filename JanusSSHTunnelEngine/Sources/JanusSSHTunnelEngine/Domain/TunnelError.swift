import Foundation

/// Janus 全局错误类型。
///
/// `LocalizedError` 让 UI 可以直接 `.errorDescription` 拿到展示文案,
/// `Equatable` 让日志系统能做去重。
enum TunnelError: Error, LocalizedError, Equatable, Sendable {
    case profileNotFound(UUID)
    case duplicateLocalPort(UInt16)
    case crossProfileLocalPortConflict(port: UInt16, occupiedBy: [UUID])
    case localPortUnavailable(UInt16)
    case sshBinaryNotFound(path: String)
    case sshSpawnFailed(code: Int32)
    case sshExited(code: Int32, signal: Int32?, reason: TerminationReason)
    case sshConfigResolutionFailed(host: String)
    case hostUnknown(String)
    case authenticationFailed(host: String)
    case networkUnreachable(host: String)

    var errorDescription: String? {
        switch self {
        case .profileNotFound(let id):
            return "Profile not found: \(id.uuidString.prefix(8))"
        case .duplicateLocalPort(let port):
            return "Local Port \(port) is duplicated within this profile."
        case .crossProfileLocalPortConflict(let port, let occupied):
            let names = occupied.map { $0.uuidString.prefix(8) }.joined(separator: ", ")
            return "Local Port \(port) conflicts with profile(s): \(names)"
        case .localPortUnavailable(let port):
            return "Local Port \(port) is already in use on this machine."
        case .sshBinaryNotFound(let path):
            return "SSH binary not found at \(path)."
        case .sshSpawnFailed(let code):
            return "Failed to spawn SSH (code \(code))."
        case .sshExited(let code, let signal, let reason):
            switch reason {
            case .userRequested: return "SSH stopped by user."
            case .applicationShutdown: return "SSH stopped during app shutdown."
            case .startupFailure: return "SSH failed to start (exit \(code))."
            case .processExited:
                if let sig = signal {
                    return "SSH exited (code \(code), signal \(sig))."
                }
                return "SSH exited (code \(code))."
            }
        case .sshConfigResolutionFailed(let host):
            return "Failed to resolve SSH host '\(host)' via ssh -G."
        case .hostUnknown(let host):
            return "Unknown SSH host '\(host)'."
        case .authenticationFailed(let host):
            return "SSH authentication failed for '\(host)'."
        case .networkUnreachable(let host):
            return "Network unreachable for '\(host)'."
        }
    }
}
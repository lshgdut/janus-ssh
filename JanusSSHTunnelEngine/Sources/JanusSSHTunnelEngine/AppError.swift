import Foundation

public enum AppError: Error, Sendable, Equatable, LocalizedError {
    // 业务
    case profileNotFound(id: UUID)
    case duplicateProfileName(name: String)
    case crossProfileLocalPortConflict(port: UInt16, ownerProfileID: UUID)
    case sshHostUnknown(alias: String)
    case sshConfigResolutionFailed(alias: String, reason: String)
    case authenticationFailed(alias: String)
    case networkUnreachable(alias: String, reason: String)

    // 生命周期
    case sshBinaryNotFound
    case sshSpawnFailed(underlying: String)
    case sshExited(code: Int32?, signal: Int32?, reason: TerminationReason)

    // 持久化
    case io(path: String, source: String)
    case decode(path: String, source: String)
    case encode(path: String, source: String)
    case schemaVersionTooNew(found: Int, supported: Int)
    case schemaVersionTooOld(found: Int, supported: Int)
    case backupFailed(path: String, source: String)
    case lockUnavailable(resource: String)

    // 验证
    case validation(issues: [ValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .profileNotFound(let id):
            return "Profile not found: \(id)"
        case .duplicateProfileName(let name):
            return "Profile name already in use: \(name)"
        case .crossProfileLocalPortConflict(let port, _):
            return "Local port \(port) is used by another profile"
        case .sshHostUnknown(let alias):
            return "SSH host '\(alias)' is not in ~/.ssh/config"
        case .sshConfigResolutionFailed(let alias, let reason):
            return "Failed to resolve SSH host '\(alias)': \(reason)"
        case .authenticationFailed(let alias):
            return "SSH authentication failed for '\(alias)'"
        case .networkUnreachable(let alias, let reason):
            return "SSH host '\(alias)' unreachable: \(reason)"
        case .sshBinaryNotFound:
            return "/usr/bin/ssh not found"
        case .sshSpawnFailed(let underlying):
            return "SSH spawn failed: \(underlying)"
        case .sshExited(let code, let signal, _):
            return "SSH exited (code: \(code.map(String.init) ?? "nil"), signal: \(signal.map(String.init) ?? "nil"))"
        case .io(let path, let source):
            return "I/O error at \(path): \(source)"
        case .decode(let path, let source):
            return "Decode error at \(path): \(source)"
        case .encode(let path, let source):
            return "Encode error at \(path): \(source)"
        case .schemaVersionTooNew(let found, let supported):
            return "Config file is from a newer version (found: \(found), supported: \(supported))"
        case .schemaVersionTooOld(let found, let supported):
            return "Config file is too old (found: \(found), supported: \(supported))"
        case .backupFailed(let path, let source):
            return "Backup failed at \(path): \(source)"
        case .lockUnavailable(let resource):
            return "Resource locked: \(resource)"
        case .validation(let issues):
            return "Validation failed: \(issues.count) issue(s)"
        }
    }
}
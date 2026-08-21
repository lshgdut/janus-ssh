import Foundation

/// SSHProcessHandle 是 SSHProcess 的对外接口 — 让 TunnelManager 不直接依赖 SSHProcess。
/// 实际生产实现就是 SSHProcess;测试中可用 FakeSSHProcessHandle。
public protocol SSHProcessHandle: Sendable {
    func events() async -> AsyncStream<SSHProcess.Event>
    func terminate(gracefully: Bool) async throws
    func pid() async -> Int32?
}

/// SSHProcessManager 协议 — 抽象层让 TunnelManager 可测试
public protocol SSHProcessManaging: Sendable {
    func launch(profileID: UUID, command: SSHCommand) async throws -> SSHProcessHandle
    func terminate(profileID: UUID, reason: TerminationReason) async
    func terminateAll(reason: TerminationReason) async
    func handle(for profileID: UUID) async -> SSHProcessHandle?
}

/// 默认实现 — 用 SSHProcess actor
public actor SSHProcessManager: SSHProcessManaging {
    public init() {}
    private var handles: [UUID: SSHProcessHandle] = [:]
    private var processes: [UUID: SSHProcess] = [:]

    public func launch(profileID: UUID, command: SSHCommand) async throws -> SSHProcessHandle {
        let proc = try SSHProcess(
            executable: command.executable,
            arguments: command.arguments,
            environment: command.environment,
            workingDirectory: command.workingDirectory
        )
        try await proc.start()
        processes[profileID] = proc
        handles[profileID] = proc
        return proc
    }

    public func terminate(profileID: UUID, reason: TerminationReason) async {
        guard let proc = processes[profileID] else { return }
        // userRequested / applicationShutdown 用 SIGTERM(graceful)
        // processExited / startupFailure 应该已经在外面处理
        let graceful: Bool
        switch reason {
        case .userRequested, .applicationShutdown:
            graceful = true
        default:
            graceful = false
        }
        try? await proc.terminate(gracefully: graceful)
        processes.removeValue(forKey: profileID)
    }

    public func terminateAll(reason: TerminationReason) async {
        let ids = Array(processes.keys)
        for id in ids {
            await terminate(profileID: id, reason: reason)
        }
    }

    public func handle(for profileID: UUID) async -> SSHProcessHandle? {
        handles[profileID]
    }
}
import Foundation

/// SSHProcessHandle 是 SSHProcess 的对外接口 — 让 TunnelManager 不直接依赖 SSHProcess。
/// 实际生产实现就是 SSHProcess;测试中可用 FakeSSHProcessHandle。
protocol SSHProcessHandle: Sendable {
    func events() async -> AsyncStream<SSHProcess.Event>
    func terminate(gracefully: Bool) async throws
    func pid() async -> Int32?
}

/// SSHProcessManager 协议 — 抽象层让 TunnelManager 可测试
protocol SSHProcessManaging: Sendable {
    func launch(profileID: UUID, command: SSHCommand) async throws -> SSHProcessHandle
    func terminate(profileID: UUID, reason: TerminationReason) async
    func terminateAll(reason: TerminationReason) async
    func handle(for profileID: UUID) async -> SSHProcessHandle?
}

/// 默认实现 — 用 SSHProcess actor
actor SSHProcessManager: SSHProcessManaging {
    private var handles: [UUID: SSHProcessHandle] = [:]
    private var processes: [UUID: SSHProcess] = [:]

    func launch(profileID: UUID, command: SSHCommand) async throws -> SSHProcessHandle {
        let proc = try SSHProcess(
            executable: command.executable,
            arguments: command.arguments,
            environment: command.environment
        )
        try await proc.start()
        processes[profileID] = proc
        handles[profileID] = proc
        return proc
    }

    func terminate(profileID: UUID, reason: TerminationReason) async {
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

    func terminateAll(reason: TerminationReason) async {
        let ids = Array(processes.keys)
        for id in ids {
            await terminate(profileID: id, reason: reason)
        }
    }

    func handle(for profileID: UUID) async -> SSHProcessHandle? {
        handles[profileID]
    }
}
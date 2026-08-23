import Foundation
import os

/// SSHProcessHandle 是 SSHProcess 的对外接口 — 让 TunnelManager 不直接依赖 SSHProcess。
/// 实际生产实现就是 SSHProcess;测试中可用 FakeSSHProcessHandle。
public protocol SSHProcessHandle: Sendable {
    func events() async -> AsyncStream<SSHProcess.Event>
    func terminate(gracefully: Bool) async throws
    /// 同步、立即终止整个进程组,不等待。供 App willTerminate 路径使用。
    func terminateNow()
    func pid() async -> Int32?
}

/// SSHProcessManager 协议 — 抽象层让 TunnelManager 可测试
public protocol SSHProcessManaging: Sendable {
    func launch(profileID: UUID, command: SSHCommand) async throws -> SSHProcessHandle
    func terminate(profileID: UUID, reason: TerminationReason) async
    func terminateAll(reason: TerminationReason) async
    /// 同步、立即终止所有运行中的 SSH 进程组。供 App willTerminate 使用 — 不 await。
    func terminateAllNow()
    func handle(for profileID: UUID) async -> SSHProcessHandle?
}

/// 默认实现 — 用 SSHProcess actor
public actor SSHProcessManager: SSHProcessManaging {
    public init() {}
    private var handles: [UUID: SSHProcessHandle] = [:]
    private var processes: [UUID: SSHProcess] = [:]

    /// 独立于 actor 存储的活跃 PID 集合,供 willTerminate 同步路径访问。
    /// os.UnfairLock 保护并发读写;只在 launch/terminate 处更新,
    /// terminateAllNow() 同步读出并 SIGKILL。
    private let livePIDs = OSAllocatedUnfairLock<[Int32]>(initialState: [])

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
        if let pid = await proc.pid() {
            livePIDs.withLock { $0.append(pid) }
        }
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
        let pid = await proc.pid()
        try? await proc.terminate(gracefully: graceful)
        if let pid = pid {
            livePIDs.withLock { $0.removeAll { $0 == pid } }
        }
        processes.removeValue(forKey: profileID)
    }

    public func terminateAll(reason: TerminationReason) async {
        let ids = Array(processes.keys)
        for id in ids {
            await terminate(profileID: id, reason: reason)
        }
    }

    /// 同步、不等待地 SIGKILL 所有活跃 SSH 进程组。
    /// 供 App willTerminate 使用 — 在 main thread 同步通知 handler 内调用,
    /// 不依赖 actor 串行化队列,即使 App 立刻退出也能保证 SIGKILL 已下发。
    public nonisolated func terminateAllNow() {
        let snapshot = livePIDs.withLock { state -> [Int32] in
            let s = state
            state.removeAll()
            return s
        }
        for pid in snapshot {
            // 负号 PID = 进程组 kill,清掉 SSH 派生的 ProxyCommand 等子进程
            _ = kill(-pid, SIGKILL)
        }
    }

    public func handle(for profileID: UUID) async -> SSHProcessHandle? {
        handles[profileID]
    }
}
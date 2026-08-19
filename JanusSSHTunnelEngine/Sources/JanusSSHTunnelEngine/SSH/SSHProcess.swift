import Foundation

/// SSHProcess 错误
public enum SSHProcessError: Error, LocalizedError {
    case notStarted
    case alreadyRunning
    case spawnFailed(underlying: Error)
    case binaryNotFound(URL)
    case invalidExecutable(String)

    public var errorDescription: String? {
        switch self {
        case .notStarted: return "Process has not been started."
        case .alreadyRunning: return "Process is already running."
        case .spawnFailed(let e): return "Failed to spawn process: \(e.localizedDescription)"
        case .binaryNotFound(let url): return "Binary not found at \(url.path)."
        case .invalidExecutable(let path): return "Not a valid executable: \(path)"
        }
    }
}

/// SSHProcess 是 SSH Engine 的核心 actor。
///
/// 把 Foundation.Process 包成 actor,
/// 串行化所有 Start / Stop / Terminate 操作,避免竞态。
///
/// 关键不变量:
/// 1. stdout / stderr / termination 三流合一,通过 `events()` 暴露
/// 2. 不调用 `waitUntilExit()`(会阻塞导致 pipe buffer 满 → 子进程卡死)
/// 3. graceful=false 时发 SIGKILL;graceful=true 发 SIGTERM 并等 5s
public actor SSHProcess: SSHProcessHandle {

    public enum Event: Sendable {
        case stdout(Data)
        case stderr(Data)
        case terminated(exitCode: Int32, reason: ProcessEndedReason)
    }

    public enum ProcessEndedReason: Sendable {
        case exited       // 正常 exit(可能被我们 SIGTERM 后)
        case killed       // SIGKILL
        case spawnFailed
        case interrupted  // SIGINT
    }

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    public init(executable: URL, arguments: [String], environment: [String: String]? = nil) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw SSHProcessError.binaryNotFound(executable)
        }
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }

    /// 启动进程,捕获 stdout / stderr,设置 terminationHandler
    func start() async throws {
        guard process == nil else {
            throw SSHProcessError.alreadyRunning
        }

        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        if let env = environment {
            p.environment = env
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        // 设置 terminationHandler — 在 actor 外触发,通过 Task 回流到 actor
        p.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            Task { await self.handleTermination(process: proc) }
        }

        do {
            try p.run()
        } catch {
            throw SSHProcessError.spawnFailed(underlying: error)
        }

        self.process = p
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe

        // 在子线程读取 stdout / stderr,转成 Event 发给所有订阅者
        // 必须在 actor 外启动 read,以免阻塞 actor 的串行化
        startReading(pipe: outPipe, kind: .stdout)
        startReading(pipe: errPipe, kind: .stderr)
    }

    /// 阻塞直到进程退出,返回 exit code
    func waitForExit() async throws -> Int32 {
        guard let p = process else {
            throw SSHProcessError.notStarted
        }
        // 如果进程已退出,直接返回(避免覆盖 terminationHandler)
        if !p.isRunning {
            return p.terminationStatus
        }
        // 用轮询而不是覆盖 terminationHandler — 保留它用于事件广播
        while p.isRunning {
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
        return p.terminationStatus
    }

    /// 优雅或强制终止
    public func terminate(gracefully: Bool) async throws {
        guard let p = process, p.isRunning else {
            throw SSHProcessError.notStarted
        }

        if gracefully {
            p.terminate()  // SIGTERM
            // 等最多 5 秒
            try await waitWithTimeout(5.0) { [weak self] in
                guard let self = self else { return true }
                return await self.process?.isRunning == false
            }
        }

        // 还在跑就 SIGKILL
        if let p = process, p.isRunning {
            kill(pid_t(p.processIdentifier), SIGKILL)
            // 等实际退出(避免上层立即 removeValue 时 Process 还在跑)
            try await waitWithTimeout(2.0) { [weak self] in
                guard let self = self else { return true }
                return await self.process?.isRunning == false
            }
        }
    }

    public func pid() -> Int32? {
        process?.processIdentifier
    }

    /// 订阅事件流(每次调用返回独立流)
    public func events() async -> AsyncStream<Event> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    // MARK: - Private

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }

    private enum IOKind { case stdout, stderr }

    private func startReading(pipe: Pipe, kind: IOKind) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let self = self else {
                fh.readabilityHandler = nil
                return
            }
            let event: Event = (kind == .stdout) ? .stdout(data) : .stderr(data)
            Task { await self.broadcast(event) }
        }
    }

    private func broadcast(_ event: Event) {
        for c in continuations.values {
            c.yield(event)
        }
    }

    private func handleTermination(process: Process) {
        let reason: ProcessEndedReason
        if process.terminationReason == .uncaughtSignal {
            reason = .killed
        } else if process.terminationStatus == 130 {
            reason = .interrupted
        } else {
            reason = .exited
        }
        let exitCode = process.terminationStatus
        let event = Event.terminated(exitCode: exitCode, reason: reason)

        // 清空 pipe handle
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        broadcast(event)
        // 标记 process 已退出
        self.process = nil
    }

    private func waitWithTimeout(_ seconds: TimeInterval, condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }
    }
}
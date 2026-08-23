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
    private let workingDirectory: String?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    /// 进程组 ID — 用于 SIGKILL 整个进程组,杀掉 SSH 派生的子进程。
    /// 由 setpgid 在 start() 里设置。
    /// nonisolated(unsafe) 是安全的:写入只在 start() 内一次,
    /// 读只在 terminateNow() 内;terminateNow() 调用方需要的是"尽快读到 PID",
    /// 即便读到未初始化的 0 也只会让 kill(0, SIGKILL) 失败(无害)。
    nonisolated(unsafe) private var processGroupID: pid_t = 0

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw SSHProcessError.binaryNotFound(executable)
        }
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
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
        if let cwd = workingDirectory {
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        // 显式设置 stdin 为 /dev/null
        // GUI app 启动的子进程没有 stdin tty,SSH 可能 block 或 exit
        p.standardInput = FileHandle.nullDevice

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

        // 把 SSH 子进程放进独立的 process group,这样:
        // 1. terminate 时能 kill 整个 group,清掉 SSH 派生的 ProxyCommand / askpass 等子进程
        // 2. 不会误伤本 App 的其它子进程(默认共享父进程 group)
        let sshPID = p.processIdentifier
        _ = setpgid(sshPID, sshPID)
        self.processGroupID = sshPID

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

    /// 优雅或强制终止(异步,会等待进程退出)
    public func terminate(gracefully: Bool) async throws {
        guard let p = process, p.isRunning else {
            throw SSHProcessError.notStarted
        }

        if gracefully {
            p.terminate()  // SIGTERM(Foundation API,只发给主进程)
            try await waitWithTimeout(5.0) { [weak self] in
                guard let self = self else { return true }
                return await self.process?.isRunning == false
            }
        }

        // 还在跑就 SIGKILL 整个 process group,把 SSH 派生的子进程也一并清掉
        if let p = process, p.isRunning {
            let pgid = pid_t(p.processIdentifier)
            _ = kill(-pgid, SIGKILL)
            try await waitWithTimeout(2.0) { [weak self] in
                guard let self = self else { return true }
                return await self.process?.isRunning == false
            }
        }
    }

    /// 同步、立即、不等待的终止。
    /// 用于 App willTerminate 这种"马上要退、没时间等"的场景。
    /// 直接 SIGKILL 整个 process group,不等子进程退出。
    /// nonisolated — 必须能从 SSHProcessHandle 协议 / actor 外部同步调用。
    /// 通过缓存 processGroupID(在 start() 里 setpgid 后写入)避免 actor 隔离。
    public nonisolated func terminateNow() {
        let pgid = processGroupID
        guard pgid > 0 else { return }
        _ = kill(-pgid, SIGKILL)
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
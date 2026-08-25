import XCTest
@testable import JanusSSHTunnelEngine

/// SSHProcess 是 SSH Engine 的核心 — 把 Foundation.Process 包成 actor,
/// 提供 stdout / stderr / termination 三流合一。
///
/// 测试策略:不依赖真实 ssh(那需要测试服务器),
/// 而是构造一个用 `/bin/echo` 或 `/bin/sleep` 作为可执行文件的假命令,
/// 验证 actor 的生命周期、流读取、终止语义。
/// Test-only 数据收集 actor — Swift 6 拒绝 `var xx` 在 @Sendable closure 里
/// mutate(capture 数据竞争),用 actor 收敛。多个测试方法都复用。
private actor BytesCollector {
    var data = Data()
    func append(_ chunk: Data) { data.append(chunk) }
}

final class SSHProcessTests: XCTestCase {

    func test_actor_serializes_state_changes() async throws {
        // actor 的存在本身就是测试目标 — 验证可以并发调用 start/stop 而不崩溃
        let proc = try SSHProcess(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["0.5"]
        )

        try await proc.start()
        let pid = await proc.pid()
        XCTAssertNotNil(pid)

        try await proc.terminate(gracefully: true)
    }

    func test_start_emits_termination_event() async throws {
        let proc = try SSHProcess(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        )

        let eventsTask = Task<[SSHProcess.Event], Error> {
            var collected: [SSHProcess.Event] = []
            for await event in await proc.events() {
                collected.append(event)
                if case .terminated = event {
                    return collected
                }
                if collected.count > 100 { return collected }  // safety
            }
            return collected
        }

        try await proc.start()
        try await proc.waitForExit()

        let events = try await eventsTask.value

        let hasTerminated = events.contains { event in
            if case .terminated = event { return true }
            return false
        }
        XCTAssertTrue(hasTerminated, "expected at least one .terminated event")
    }

    func test_start_captures_stdout() async throws {
        let proc = try SSHProcess(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["janus-output"]
        )

        // 之前用 `var stdoutBytes` 在 Task 里 mutate — Swift 6 拒绝(capture 数据竞争),
        // 用 actor 收敛(BytesCollector 在文件顶部)。
        let collector = BytesCollector()
        let consumer = Task {
            for await event in await proc.events() {
                switch event {
                case .stdout(let data):
                    await collector.append(data)  // actor 内部串行化
                case .terminated:
                    return
                default: break
                }
            }
        }

        try await proc.start()
        try await proc.waitForExit()
        await consumer.value

        let stdoutBytes = await collector.data
        let text = String(data: stdoutBytes, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("janus-output"),
                      "stdout should contain echo output, got: \(text)")
    }

    func test_start_captures_stderr() async throws {
        // /bin/sh -c 'echo err >&2' — 强制写 stderr
        let proc = try SSHProcess(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo janus-error >&2; exit 0"]
        )

        let collector = BytesCollector()  // 文件顶部 reuse
        let consumer = Task {
            for await event in await proc.events() {
                switch event {
                case .stderr(let data):
                    await collector.append(data)
                case .terminated:
                    return
                default: break
                }
            }
        }

        try await proc.start()
        try await proc.waitForExit()
        await consumer.value

        let stderrBytes = await collector.data
        let text = String(data: stderrBytes, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("janus-error"),
                      "stderr should contain echo output, got: \(text)")
    }

    func test_double_start_throws() async throws {
        let proc = try SSHProcess(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["x"]
        )
        try await proc.start()
        do {
            try await proc.start()
            XCTFail("expected alreadyRunning error")
        } catch SSHProcessError.alreadyRunning {
            // expected
        }
        try await proc.terminate(gracefully: true)
    }

    func test_terminate_before_start_throws() async throws {
        let proc = try SSHProcess(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["x"]
        )
        do {
            try await proc.terminate(gracefully: true)
            XCTFail("expected notStarted error")
        } catch SSHProcessError.notStarted {
            // expected
        }
    }

    func test_pid_is_nil_before_start() async throws {
        let proc = try SSHProcess(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["x"]
        )
        let pid = await proc.pid()
        XCTAssertNil(pid)
    }
}
// verify_main.swift
// 独立的可执行验证程序 — 在没有 XCTest/Swift Testing 链接的
// CommandLineTools 环境下直接调用 JanusSSHTunnelEngine 的 API 进行行为验证。

import Foundation
// 编译时与 source files 一起 build,所有类型都是 in-module

@main
struct Verify {
    static func main() {
        var passed = 0
        var failed = 0

        func check(_ label: String, _ condition: Bool) {
            if condition {
                passed += 1
                print("✓ \(label)")
            } else {
                failed += 1
                print("✗ \(label)")
            }
        }

        // ─── Profile ───
        let original = Profile(
            name: "Production",
            sshHostAlias: "production",
            forwards: [
                PortForward(localHost: "127.0.0.1", localPort: 15432,
                            remoteHost: "10.20.0.15", remotePort: 5432, label: "postgres"),
                PortForward(localHost: "127.0.0.1", localPort: 16379,
                            remoteHost: "10.20.0.16", remotePort: 6379, label: "redis")
            ],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: true),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        // Profile Codable round-trip
        do {
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(Profile.self, from: encoded)
            check("Profile roundtrips through Codable", decoded == original)
            let json = String(data: encoded, encoding: .utf8) ?? ""
            check("Profile JSON excludes pid/state/startedAt",
                  !json.contains("pid") && !json.contains("state") && !json.contains("startedAt"))
        } catch {
            check("Profile Codable roundtrip", false)
        }

        let p1 = Profile(name: "A", sshHostAlias: "a", forwards: [],
                         behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
                         createdAt: Date(), updatedAt: Date())
        let p2 = Profile(name: "A", sshHostAlias: "a", forwards: [],
                         behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
                         createdAt: Date(), updatedAt: Date())
        check("Profile IDs are unique", p1.id != p2.id)

        // ─── PortForward ───
        let f1 = PortForward(localHost: "127.0.0.1", localPort: 15432,
                             remoteHost: "10.20.0.15", remotePort: 5432, label: "postgres")
        check("PortForward.localEndpoint", f1.localEndpoint == "127.0.0.1:15432")
        check("PortForward.sshArgument", f1.sshArgument == "127.0.0.1:15432:10.20.0.15:5432")

        let fa = PortForward(localHost: "127.0.0.1", localPort: 1,
                             remoteHost: "r", remotePort: 1, label: Optional<String>.none)
        let fb = PortForward(localHost: "127.0.0.1", localPort: 1,
                             remoteHost: "r", remotePort: 1, label: Optional<String>.none)
        check("PortForward IDs are unique", fa.id != fb.id)

        // ─── Tunnel & ProfileSnapshot ───
        let snap = ProfileSnapshot(original)
        check("ProfileSnapshot preserves id", snap.id == original.id)
        check("ProfileSnapshot preserves name", snap.name == "Production")
        check("ProfileSnapshot preserves autoReconnect", snap.autoReconnect == true)
        check("ProfileSnapshot preserves autoStart", snap.autoStart == true)

        let tunnel = Tunnel(profileSnapshot: snap, state: .running, pid: 41928)
        check("Tunnel id == snapshot id", tunnel.id == snap.id)
        check("Tunnel state == .running", tunnel.state == .running)
        check("Tunnel pid recorded", tunnel.pid == 41928)

        check("running != reconnecting", TunnelState.running != TunnelState.reconnecting)

        // ─── TerminationReason 穷尽性 ───
        let reasons: Set<TerminationReason> = [
            .userRequested, .processExited, .applicationShutdown, .startupFailure
        ]
        check("TerminationReason has 4 distinct cases", reasons.count == 4)

        // ─── TunnelError Equatable + 描述 ───
        let e1 = TunnelError.duplicateLocalPort(15432)
        let e2 = TunnelError.duplicateLocalPort(15432)
        let e3 = TunnelError.duplicateLocalPort(16379)
        check("TunnelError Equatable (same)", e1 == e2)
        check("TunnelError Equatable (different)", e1 != e3)

        if case let .crossProfileLocalPortConflict(port, ids) =
            TunnelError.crossProfileLocalPortConflict(port: 15432, occupiedBy: [UUID(), UUID()]) {
            check("crossProfileLocalPortConflict port", port == 15432)
            check("crossProfileLocalPortConflict ids count", ids.count == 2)
        } else {
            check("crossProfileLocalPortConflict pattern", false)
        }

        let unavailable = TunnelError.localPortUnavailable(8080)
        check("localPortUnavailable description includes port",
              unavailable.errorDescription?.contains("8080") == true)

        // ─── ProfileValidator ───
        let knownHosts: Set<String> = ["production", "staging", "bastion"]
        let v = ProfileValidator()
        let defaultBehavior = Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false)

        // Valid profile
        let valid = Profile(
            name: "Production", sshHostAlias: "production",
            forwards: [PortForward(localHost: "127.0.0.1", localPort: 15432,
                                    remoteHost: "10.20.0.15", remotePort: 5432, label: Optional<String>.none)],
            behavior: defaultBehavior, createdAt: Date(), updatedAt: Date()
        )
        let validIssues = v.validate(valid, knownHosts: knownHosts)
        check("Valid profile has no errors",
              validIssues.filter { $0.severity == .error }.isEmpty)

        // Empty name
        var bad = valid
        bad.name = ""
        let nameIssues = v.validate(bad, knownHosts: knownHosts)
        check("Empty name → error on field 'name'",
              nameIssues.contains { $0.severity == .error && $0.field == "name" })

        // Unknown host
        bad = valid
        bad.sshHostAlias = "ghost"
        let hostIssues = v.validate(bad, knownHosts: knownHosts)
        check("Unknown sshHostAlias → error",
              hostIssues.contains { $0.severity == .error && $0.field == "sshHostAlias" })

        // Zero forwards
        bad = valid
        bad.forwards = []
        let noForwardIssues = v.validate(bad, knownHosts: knownHosts)
        check("Zero forwards → error on 'forwards'",
              noForwardIssues.contains { $0.severity == .error && $0.field == "forwards" })

        // Duplicate localPort
        bad = valid
        bad.forwards = [
            PortForward(localHost: "127.0.0.1", localPort: 15432,
                        remoteHost: "10.20.0.15", remotePort: 5432, label: Optional<String>.none),
            PortForward(localHost: "127.0.0.1", localPort: 15432,
                        remoteHost: "10.20.0.16", remotePort: 6379, label: Optional<String>.none)
        ]
        let dupIssues = v.validate(bad, knownHosts: knownHosts)
        check("Duplicate local port → error",
              dupIssues.contains { $0.severity == .error && $0.message.contains("15432") })

        // Zero localPort
        bad = valid
        bad.forwards[0] = PortForward(localHost: "127.0.0.1", localPort: 0,
                                      remoteHost: "10.20.0.15", remotePort: 5432, label: Optional<String>.none)
        check("Zero local port → error",
              v.validate(bad, knownHosts: knownHosts).contains {
                  $0.severity == .error && ($0.field?.contains("localPort") == true)
              })

        // Note: Port > 65535 cannot be constructed (UInt16 overflows at compile time),
        // so the upper-bound check is enforced at the type system level.
        // We verify the boundary: UInt16.max (65535) is valid.

        // Port > 65535 — 65535 是 UInt16 上限,溢出会触发编译错误,所以这里在边界测试
        // UInt16.max (65535) 应该被接受
        bad = valid
        bad.forwards[0] = PortForward(localHost: "127.0.0.1", localPort: UInt16.max,
                                      remoteHost: "10.20.0.15", remotePort: 5432, label: Optional<String>.none)
        let edgeIssues = v.validate(bad, knownHosts: knownHosts)
        check("Port 65535 (UInt16.max) is valid",
              !edgeIssues.contains { $0.severity == .error && ($0.field?.contains("localPort") == true) })

        // Empty localHost
        bad = valid
        bad.forwards[0] = PortForward(localHost: "", localPort: 15432,
                                      remoteHost: "10.20.0.15", remotePort: 5432, label: Optional<String>.none)
        check("Empty local host → error",
              v.validate(bad, knownHosts: knownHosts).contains {
                  $0.severity == .error && ($0.field?.contains("localHost") == true)
              })

        // Empty remoteHost
        bad = valid
        bad.forwards[0] = PortForward(localHost: "127.0.0.1", localPort: 15432,
                                      remoteHost: "", remotePort: 5432, label: Optional<String>.none)
        check("Empty remote host → error",
              v.validate(bad, knownHosts: knownHosts).contains {
                  $0.severity == .error && ($0.field?.contains("remoteHost") == true)
              })

        // Cross-profile conflict (new profile)
        let id = UUID()
        let existing: [Profile] = [
            Profile(id: id, name: "Production", sshHostAlias: "production",
                    forwards: [PortForward(localHost: "127.0.0.1", localPort: 15432,
                                           remoteHost: "10.20.0.15", remotePort: 5432, label: Optional<String>.none)],
                    behavior: defaultBehavior, createdAt: Date(), updatedAt: Date())
        ]
        let candidate = Profile(
            name: "Dev", sshHostAlias: "staging",
            forwards: [PortForward(localHost: "127.0.0.1", localPort: 15432,
                                   remoteHost: "10.40.0.1", remotePort: 5432, label: Optional<String>.none)],
            behavior: defaultBehavior, createdAt: Date(), updatedAt: Date()
        )
        let crossNew = v.validateForCrossProfileConflict(candidate, against: existing, excluding: nil)
        check("Cross-profile conflict (new) → error", !crossNew.isEmpty)

        // Cross-profile conflict (editing self) — should NOT report
        let editing = Profile(
            id: id, name: "Production (editing)", sshHostAlias: "production",
            forwards: [PortForward(localHost: "127.0.0.1", localPort: 15432,
                                   remoteHost: "10.20.0.15", remotePort: 5432, label: Optional<String>.none)],
            behavior: defaultBehavior, createdAt: Date(), updatedAt: Date()
        )
        let crossEdit = v.validateForCrossProfileConflict(editing, against: existing, excluding: id)
        check("Cross-profile conflict (editing self) → empty", crossEdit.isEmpty)

        // ─── M2: Persistence ───
        // main 是同步的 — 通过 Task + semaphore 把 async API 跑起来,
        // 结果用普通 class(非 actor)收集,因为我们需要在 main 里同步读取
        print("")
        print("→ Running M2 persistence tests...")
        let m2Collector = M2Result()
        let m2Semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await m2Collector.runAll()
            m2Semaphore.signal()
        }
        let waitResult = m2Semaphore.wait(timeout: .now() + 60)
        print("→ M2 wait result: \(waitResult == .success ? "ok" : "timeout")")
        print("→ M2 collected \(m2Collector.results.count) results")

        // 合并结果
        for result in m2Collector.results {
            check(result.label, result.ok)
        }

        // ─── M3: SSH Engine ───
        print("")
        print("→ Running M3 SSH engine tests...")
        let m3Collector = M3Result()
        let m3Semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await m3Collector.runAll()
            m3Semaphore.signal()
        }
        _ = m3Semaphore.wait(timeout: .now() + 30)
        print("→ M3 collected \(m3Collector.results.count) results")
        for result in m3Collector.results {
            check(result.label, result.ok)
        }

        print("")
        print(String(repeating: "─", count: 50))
        print("Result: \(passed) passed, \(failed) failed")

        if failed > 0 {
            exit(1)
        }
    }
}

/// M2 Persistence 验证 — 全部 async,结果用普通 class 收集
final class M2Result: @unchecked Sendable {
    struct Result {
        let label: String
        let ok: Bool
    }
    var results: [Result] = []
    private let lock = NSLock()

    func add(_ label: String, _ ok: Bool) {
        lock.lock()
        defer { lock.unlock() }
        results.append(Result(label: label, ok: ok))
    }

    func runAll() async {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("janus-m2-\(UUID().uuidString)")
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let profilesURL = tempDir.appendingPathComponent("profiles.json")
        let backupDir = tempDir.appendingPathComponent("backups")
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let repo = JSONProfileRepository(
            fileURL: profilesURL,
            backupDirectory: backupDir,
            maxBackups: 10
        )

        // 1. 文件不存在时抛 fileNotFound
        do {
            _ = try await repo.load()
            add("load() on missing file should throw", false)
        } catch RepositoryError.fileNotFound {
            add("load() missing file → .fileNotFound", true)
        } catch {
            add("load() wrong error type: \(error)", false)
        }

        // 2. 保存与加载 round-trip
        let p = makeM2Profile(name: "Production", alias: "production")
        do {
            try await repo.save([p])
            let loaded = try await repo.load()
            add("save + load roundtrip",
                loaded.count == 1 && loaded.first?.name == "Production")
        } catch {
            add("save + load: \(error)", false)
        }

        // 3. 备份生成
        do {
            try await repo.save([p])
            let backups = try await repo.listBackups()
            add("save creates backup (\(backups.count) files)", backups.count >= 1)
        } catch {
            add("backup creation: \(error)", false)
        }

        // 4. 备份轮转: 多次 save 后保留 10 个
        do {
            for i in 0..<13 {
                let v = makeM2Profile(name: "v\(i)", alias: "host")
                try await repo.save([v])
                try? await Task.sleep(nanoseconds: 1_100_000)
            }
            let backups = try await repo.listBackups()
            add("backup rotation keeps exactly maxBackups (10)",
                backups.count == 10)
        } catch {
            add("rotation: \(error)", false)
        }

        // 5. AtomicFileStore .bak
        let store = AtomicFileStore()
        let cfgURL = tempDir.appendingPathComponent("config.json")
        do {
            try await store.write(Data("v1".utf8), to: cfgURL)
            try await store.write(Data("v2".utf8), to: cfgURL)
            let bakURL = cfgURL.deletingPathExtension().appendingPathExtension("bak")
            let bak = try String(contentsOf: bakURL, encoding: .utf8)
            let now = try String(contentsOf: cfgURL, encoding: .utf8)
            add("AtomicFileStore creates .bak with previous content",
                bak == "v1" && now == "v2")
        } catch {
            add("AtomicFileStore: \(error)", false)
        }

        // 6. AppSettings defaults + JSON roundtrip
        do {
            let defaults = AppSettings.defaults
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(defaults)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let decoded = try dec.decode(AppSettings.self, from: data)
            let eq = decoded == defaults
            let safe = defaults.tunnel.defaultAutoReconnect
                && defaults.tunnel.exitOnForwardFailure
                && defaults.tunnel.backoffPolicy.initialDelayMs == 1000
                && defaults.tunnel.backoffPolicy.maxDelayMs == 30_000
            add("AppSettings Codable roundtrip", eq)
            add("AppSettings defaults are safe reconnect policy", safe)
        } catch {
            add("AppSettings: \(error)", false)
        }

        // 7. JSONSettingsRepository missing file → defaults
        do {
            let settingsURL = tempDir.appendingPathComponent("settings.json")
            let settingsRepo = JSONSettingsRepository(fileURL: settingsURL)
            let loaded = try await settingsRepo.load()
            add("Settings.load() missing file → defaults", loaded == AppSettings.defaults)
        } catch {
            add("Settings missing-file load: \(error)", false)
        }

        // 8. Settings save + load roundtrip
        do {
            let settingsURL = tempDir.appendingPathComponent("settings.json")
            let settingsRepo = JSONSettingsRepository(fileURL: settingsURL)
            var custom = AppSettings.defaults
            custom.general.launchAtLogin = true
            custom.ssh.configPath = "/custom/path/config"
            try await settingsRepo.save(custom)
            let loaded = try await settingsRepo.load()
            add("Settings save + load custom values", loaded == custom)
        } catch {
            add("Settings roundtrip: \(error)", false)
        }

        // 9. Schema migration: 缺 version → v1
        do {
            let noVersionJSON = #"{"profiles":[]}"#.data(using: .utf8)!
            let envelope = try JSONDecoder().decode(ProfileEnvelope.self, from: noVersionJSON)
            add("Schema migration: missing version → v1",
                envelope.version == 1 && envelope.profiles.isEmpty)
        } catch {
            add("Schema migration decode: \(error)", false)
        }

        // 10. 未知 schema version 拒绝
        do {
            let futureJSON = #"{"version":999,"profiles":[]}"#.data(using: .utf8)!
            let fURL = tempDir.appendingPathComponent("future.json")
            try futureJSON.write(to: fURL)
            let fRepo = JSONProfileRepository(
                fileURL: fURL,
                backupDirectory: tempDir.appendingPathComponent("fb")
            )
            do {
                _ = try await fRepo.load()
                add("Unknown schema version rejected", false)
            } catch RepositoryError.unsupportedVersion {
                add("Unknown schema version rejected", true)
            }
        } catch {
            add("Setup future.json: \(error)", false)
        }
    }

    private func makeM2Profile(name: String, alias: String) -> Profile {
        Profile(
            name: name,
            sshHostAlias: alias,
            forwards: [PortForward(localHost: "127.0.0.1", localPort: 15432,
                                   remoteHost: "10.20.0.15", remotePort: 5432,
                                   label: Optional<String>.none)],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

/// M3 SSH Engine 验证
final class M3Result: @unchecked Sendable {
    struct Result {
        let label: String
        let ok: Bool
    }
    var results: [Result] = []
    private let lock = NSLock()

    func add(_ label: String, _ ok: Bool) {
        lock.lock()
        defer { lock.unlock() }
        results.append(Result(label: label, ok: ok))
    }

    func runAll() async {
        // ─── SSHCommandBuilder (sync) ───
        let builder = SSHCommandBuilder()

        // 1. 强制安全 flag 存在
        do {
            let cmd = try builder.build(profile: makeSnapshot(forwards: [(1, "r", 1)]))
            let hasN = cmd.arguments.contains("-N")
            let hasExitOn = cmd.arguments.contains("ExitOnForwardFailure=yes")
            add("SSHCommandBuilder: -N 强制存在", hasN)
            add("SSHCommandBuilder: ExitOnForwardFailure=yes 强制存在", hasExitOn)
        } catch {
            add("SSHCommandBuilder: build 失败 \(error)", false)
        }

        // 2. 三个 forward → 三个 -L
        do {
            let cmd = try builder.build(profile: makeSnapshot(forwards: [
                (15432, "10.20.0.15", 5432),
                (16379, "10.20.0.16", 6379),
                (18080, "10.20.0.17", 8080)
            ]))
            let lCount = cmd.arguments.filter { $0 == "-L" }.count
            add("SSHCommandBuilder: 每个 forward 一条 -L", lCount == 3)
            add("SSHCommandBuilder: argv 包含 sshHostAlias 作为末位参数",
                cmd.arguments.last == "test-host")
            add("SSHCommandBuilder: executable 是 /usr/bin/ssh",
                cmd.executable.path == "/usr/bin/ssh")
        } catch {
            add("SSHCommandBuilder: 3-forward build \(error)", false)
        }

        // 3. 空 forwards 抛 noForwards
        do {
            _ = try builder.build(profile: makeSnapshot(forwards: []))
            add("SSHCommandBuilder: 空 forwards 应抛错", false)
        } catch SSHCommandBuilderError.noForwards {
            add("SSHCommandBuilder: 空 forwards 抛 .noForwards", true)
        } catch {
            add("SSHCommandBuilder: 空 forwards 错误类型错 \(error)", false)
        }

        // 4. 不走 shell
        do {
            let cmd = try builder.build(profile: makeSnapshot(forwards: [(1, "r", 1)]))
            add("SSHCommandBuilder: 不含 -c(不通过 shell)",
                !cmd.arguments.contains("-c"))
        } catch {
            add("SSHCommandBuilder: 不走 shell 测试失败 \(error)", false)
        }

        // 5. Production 原型 snapshot 对齐
        do {
            let cmd = try builder.build(profile: makeSnapshot(alias: "production", forwards: [
                (15432, "10.20.0.15", 5432),
                (16379, "10.20.0.16", 6379),
                (18080, "10.20.0.17", 8080)
            ]))
            let allExpected = [
                "-N", "ExitOnForwardFailure=yes",
                "127.0.0.1:15432:10.20.0.15:5432",
                "127.0.0.1:16379:10.20.0.16:6379",
                "127.0.0.1:18080:10.20.0.17:8080",
                "production"
            ].allSatisfy { cmd.arguments.contains($0) }
            add("SSHCommandBuilder: Production 原型 snapshot 完整对齐", allExpected)
        } catch {
            add("SSHCommandBuilder: Production snapshot \(error)", false)
        }

        // ─── SSHProcess (async) ───
        // 用 /bin/echo + /bin/sleep 模拟 ssh,验证 actor 行为
        await runProcessTests()
    }

    private func runProcessTests() async {
        // A. 启动后 pid 不为 nil
        do {
            let proc = try SSHProcess(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["0.5"]
            )
            try await proc.start()
            let pid = await proc.pid()
            add("SSHProcess: 启动后 pid 非 nil", pid != nil)
            try await proc.terminate(gracefully: true)
        } catch {
            add("SSHProcess: start + pid \(error)", false)
        }

        // B. 双 start 抛 alreadyRunning
        do {
            let proc = try SSHProcess(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["1.0"]
            )
            try await proc.start()
            do {
                try await proc.start()
                add("SSHProcess: 双 start 应抛错", false)
            } catch SSHProcessError.alreadyRunning {
                add("SSHProcess: 双 start 抛 .alreadyRunning", true)
            }
            try await proc.terminate(gracefully: false)
        } catch {
            add("SSHProcess: 双 start setup \(error)", false)
        }

        // C. 未启动时 terminate 抛 notStarted
        do {
            let proc = try SSHProcess(
                executable: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["x"]
            )
            do {
                try await proc.terminate(gracefully: true)
                add("SSHProcess: terminate-before-start 应抛错", false)
            } catch SSHProcessError.notStarted {
                add("SSHProcess: terminate-before-start 抛 .notStarted", true)
            }
        } catch {
            add("SSHProcess: notStarted setup \(error)", false)
        }

        // D. stdout / stderr / terminated 三流合一
        do {
            let proc = try SSHProcess(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo out-marker; echo err-marker >&2; exit 0"]
            )

            var sawOut = false
            var sawErr = false
            var sawTerm = false

            let consumer = Task {
            let stream = await proc.events()
            for await event in stream {
                switch event {
                case .stdout(let d):
                    if String(data: d, encoding: .utf8)?.contains("out-marker") == true {
                        sawOut = true
                    }
                case .stderr(let d):
                    if String(data: d, encoding: .utf8)?.contains("err-marker") == true {
                        sawErr = true
                    }
                case .terminated:
                    sawTerm = true
                    return
                }
            }
        }

            try await proc.start()
            try await proc.waitForExit()
            await consumer.value

            add("SSHProcess: stdout 包含 echo 内容", sawOut)
            add("SSHProcess: stderr 包含 echo 内容", sawErr)
            add("SSHProcess: terminated 事件触发", sawTerm)
        } catch {
            add("SSHProcess: 三流合一 \(error)", false)
        }

        // E. 二进制不存在应抛 binaryNotFound
        do {
            _ = try SSHProcess(
                executable: URL(fileURLWithPath: "/nonexistent/binary"),
                arguments: []
            )
            add("SSHProcess: 不存在的 binary 应抛错", false)
        } catch SSHProcessError.binaryNotFound {
            add("SSHProcess: binary 不存在抛 .binaryNotFound", true)
        } catch {
            add("SSHProcess: binaryNotFound 测试失败 \(error)", false)
        }
    }

    private func makeSnapshot(
        alias: String = "test-host",
        forwards: [(UInt16, String, UInt16)]
    ) -> ProfileSnapshot {
        let pf = forwards.compactMap { p, h, r -> PortForward? in
            guard p != 0, !h.isEmpty, r != 0 else { return nil }
            return PortForward(localHost: "127.0.0.1", localPort: p,
                               remoteHost: h, remotePort: r, label: nil)
        }
        let profile = Profile(
            name: "Test", sshHostAlias: alias, forwards: pf,
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: Date(), updatedAt: Date()
        )
        return ProfileSnapshot(profile)
    }
}
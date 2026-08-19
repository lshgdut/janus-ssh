import Foundation

/// SSH 配置协议 — 抽象层让测试可以替换 mock
public protocol SSHConfigProviding: Sendable {
    /// 从 ssh config 发现所有 host alias(支持 Include 递归)
    func discoverHosts() async throws -> [SSHHost]
    /// 通过 ssh -G 解析某个 host 的完整配置
    func resolve(host: String) async throws -> ResolvedHostConfig
    /// 测试某个 host 是否可达
    func testConnection(alias: String) async throws -> ConnectionTestResult
}

public enum SSHConfigError: Error, LocalizedError {
    case fileNotFound(String)
    case parseError(String)
    case resolutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "SSH config file not found: \(p)"
        case .parseError(let msg): return "Failed to parse SSH config: \(msg)"
        case .resolutionFailed(let host): return "Failed to resolve host '\(host)' via ssh -G"
        }
    }
}

/// 默认实现 — 通过文件解析 + ssh -G
public final class SSHConfigService: SSHConfigProviding, @unchecked Sendable {

    private let configPath: String
    private let sshPath: URL

    public init(configPath: String = "~/.ssh/config",
         sshPath: URL = URL(fileURLWithPath: "/usr/bin/ssh")) {
        self.configPath = configPath
        self.sshPath = sshPath
    }

    // MARK: - Discovery

    public func discoverHosts() async throws -> [SSHHost] {
        let path = expand(configPath)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SSHConfigError.fileNotFound(path)
        }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let entries = SSHConfigParser.parse(content, basePath: path)
        return entries.map { entry in
            SSHHost(
                alias: entry.alias,
                user: entry.options[.user],
                hostname: entry.options[.hostname],
                port: entry.options[.port].flatMap { Int($0) },
                identityFiles: [expand(entry.options[.identityFile] ?? "", from: path)],
                proxyJump: entry.options[.proxyJump],
                forwardAgent: entry.options[.forwardAgent].map { $0.lowercased() == "yes" },
                serverAliveInterval: entry.options[.serverAliveInterval].flatMap { Int($0) }
            )
        }
    }

    // MARK: - Resolution via ssh -G

    public func resolve(host: String) async throws -> ResolvedHostConfig {
        let proc = try SSHProcess(
            executable: sshPath,
            arguments: ["-G", host]
        )

        // 用 AsyncStream 收集 stdout,避免 data race
        let stream = await proc.events()
        let consumer = Task<[Data], Never> {
            var chunks: [Data] = []
            for await event in stream {
                if case .stdout(let d) = event { chunks.append(d) }
                if case .terminated = event { return chunks }
            }
            return chunks
        }

        try await proc.start()
        _ = try await proc.waitForExit()
        let chunks = await consumer.value
        let output = chunks.reduce(Data(), +)

        let text = String(data: output, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n").map(String.init)

        var dict: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1,
                                   omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 2 else { continue }
            dict[parts[0].lowercased()] = parts[1]
        }

        guard !dict.isEmpty else {
            throw SSHConfigError.resolutionFailed(host)
        }

        let identity = dict["identityfile"].map { [$0] } ?? []

        return ResolvedHostConfig(
            alias: host,
            user: dict["user"],
            hostname: dict["hostname"],
            port: dict["port"].flatMap { Int($0) },
            identityFiles: identity,
            proxyJump: dict["proxyjump"],
            proxyCommand: dict["proxycommand"]
        )
    }

    // MARK: - Test connection

    public func testConnection(alias: String) async throws -> ConnectionTestResult {
        let proc = try SSHProcess(
            executable: sshPath,
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
                alias, "exit"
            ]
        )

        let start = Date()
        let stream = await proc.events()
        let consumer = Task<[Data], Never> {
            var chunks: [Data] = []
            for await event in stream {
                if case .stderr(let d) = event { chunks.append(d) }
                if case .terminated = event { return chunks }
            }
            return chunks
        }

        do {
            try await proc.start()
            _ = try await proc.waitForExit()
            _ = await consumer.value
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)

            // exit 0 = 通
            return .reachable(latencyMs: elapsed)
        } catch {
            return .unreachable(reason: error.localizedDescription)
        }
    }

    // MARK: - Private

    private func expand(_ path: String, from base: String? = nil) -> String {
        var p = (path as NSString).expandingTildeInPath
        if !p.hasPrefix("/") {
            // 相对 Include — 相对 config 所在目录
            let baseDir = (base as NSString?)?.deletingLastPathComponent ?? NSHomeDirectory()
            p = (baseDir as NSString).appendingPathComponent(p)
        }
        return p
    }
}
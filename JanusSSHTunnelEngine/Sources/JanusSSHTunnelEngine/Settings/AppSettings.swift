import Foundation

/// 全局应用设置 — 与 Profile 分离存储
///
/// 文件不存在时,JSONSettingsRepository 会返回 `AppSettings.defaults`
/// (首次启动语义)。
struct AppSettings: Codable, Equatable, Sendable {
    var version: Int
    var general: General
    var ssh: SSHConfig
    var tunnel: TunnelDefaults

    init(
        version: Int = SchemaVersion.current.rawValue,
        general: General = .defaults,
        ssh: SSHConfig = .defaults,
        tunnel: TunnelDefaults = .defaults
    ) {
        self.version = version
        self.general = general
        self.ssh = ssh
        self.tunnel = tunnel
    }

    static let defaults = AppSettings()

    struct General: Codable, Equatable, Sendable {
        var launchAtLogin: Bool
        var showMenuBarIcon: Bool
        var quitOnWindowClose: Bool

        static let defaults = General(
            launchAtLogin: false,
            showMenuBarIcon: true,
            quitOnWindowClose: false
        )
    }

    struct SSHConfig: Codable, Equatable, Sendable {
        var configPath: String
        var resolveIncludes: Bool

        static let defaults = SSHConfig(
            configPath: "~/.ssh/config",
            resolveIncludes: true
        )
    }

    struct TunnelDefaults: Codable, Equatable, Sendable {
        var defaultAutoReconnect: Bool
        var defaultPortConflictCheck: Bool
        var exitOnForwardFailure: Bool
        var backoffPolicy: BackoffPolicy

        static let defaults = TunnelDefaults(
            defaultAutoReconnect: true,
            defaultPortConflictCheck: true,
            exitOnForwardFailure: true,
            backoffPolicy: .defaults
        )
    }
}

/// 指数退避策略 — 对齐 ChatGPT 方案中的 1s / 2s / 5s / 10s / 30s 节奏
struct BackoffPolicy: Codable, Equatable, Sendable {
    /// 首次重试前的等待时间(毫秒)
    var initialDelayMs: Int
    /// 每次失败后的乘数(2.0 = 指数退避)
    var multiplier: Double
    /// 单次等待的最大值(毫秒)
    var maxDelayMs: Int
    /// 最大重试次数(nil = 无限)
    var maxAttempts: Int?

    static let defaults = BackoffPolicy(
        initialDelayMs: 1000,
        multiplier: 2.0,
        maxDelayMs: 30_000,
        maxAttempts: nil
    )
}
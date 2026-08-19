import Foundation

/// 全局应用设置 — 与 Profile 分离存储
///
/// 文件不存在时,JSONSettingsRepository 会返回 `AppSettings.defaults`
/// (首次启动语义)。
public struct AppSettings: Codable, Equatable, Sendable {
    public var version: Int
    public var general: General
    public var ssh: SSHConfig
    public var tunnel: TunnelDefaults

    public init(
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

    public static let defaults = AppSettings()

    public struct General: Codable, Equatable, Sendable {
        public var launchAtLogin: Bool
        public var showMenuBarIcon: Bool
        public var quitOnWindowClose: Bool

        public static let defaults = General(
            launchAtLogin: false,
            showMenuBarIcon: true,
            quitOnWindowClose: false
        )
    }

    public struct SSHConfig: Codable, Equatable, Sendable {
        public var configPath: String
        public var resolveIncludes: Bool

        public static let defaults = SSHConfig(
            configPath: "~/.ssh/config",
            resolveIncludes: true
        )
    }

    public struct TunnelDefaults: Codable, Equatable, Sendable {
        public var defaultAutoReconnect: Bool
        public var defaultPortConflictCheck: Bool
        public var exitOnForwardFailure: Bool
        public var backoffPolicy: BackoffPolicy

        public static let defaults = TunnelDefaults(
            defaultAutoReconnect: true,
            defaultPortConflictCheck: true,
            exitOnForwardFailure: true,
            backoffPolicy: .defaults
        )
    }
}

/// 指数退避策略 — 对齐 ChatGPT 方案中的 1s / 2s / 5s / 10s / 30s 节奏
public struct BackoffPolicy: Codable, Equatable, Sendable {
    /// 首次重试前的等待时间(毫秒)
    public var initialDelayMs: Int
    /// 每次失败后的乘数(2.0 = 指数退避)
    public var multiplier: Double
    /// 单次等待的最大值(毫秒)
    public var maxDelayMs: Int
    /// 最大重试次数(nil = 无限)
    public var maxAttempts: Int?

    public static let defaults = BackoffPolicy(
        initialDelayMs: 1000,
        multiplier: 2.0,
        maxDelayMs: 30_000,
        maxAttempts: nil
    )
}
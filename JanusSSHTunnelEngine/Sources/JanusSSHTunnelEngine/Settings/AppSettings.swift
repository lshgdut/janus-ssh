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
        public var theme: Theme

        public init(
            launchAtLogin: Bool,
            showMenuBarIcon: Bool,
            quitOnWindowClose: Bool,
            theme: Theme
        ) {
            self.launchAtLogin = launchAtLogin
            self.showMenuBarIcon = showMenuBarIcon
            self.quitOnWindowClose = quitOnWindowClose
            self.theme = theme
        }

        public static let defaults = General(
            launchAtLogin: false,
            showMenuBarIcon: true,
            quitOnWindowClose: false,
            theme: .system
        )

        // 自定义解码 — 让旧 settings.json (没有 theme 字段) 也能解码,
        // 缺字段时回退到默认值。否则旧用户升级后所有设置都被刷回 defaults。
        enum CodingKeys: String, CodingKey {
            case launchAtLogin, showMenuBarIcon, quitOnWindowClose, theme
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            launchAtLogin    = try c.decodeIfPresent(Bool.self,  forKey: .launchAtLogin)    ?? Self.defaults.launchAtLogin
            showMenuBarIcon  = try c.decodeIfPresent(Bool.self,  forKey: .showMenuBarIcon)  ?? Self.defaults.showMenuBarIcon
            quitOnWindowClose = try c.decodeIfPresent(Bool.self, forKey: .quitOnWindowClose) ?? Self.defaults.quitOnWindowClose
            theme            = try c.decodeIfPresent(Theme.self, forKey: .theme)            ?? Self.defaults.theme
        }
    }

    /// App 主题偏好。`.system` 跟系统外观,`.light` / `.dark` 强制覆盖 —
    /// 包括 NSPopover 这种不走 SwiftUI Scene 的宿主(走 NSApp.appearance)。
    public enum Theme: String, Codable, Sendable, CaseIterable {
        case system
        case light
        case dark
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
import SwiftUI
import Observation
import JanusSSHTunnelEngine

/// 依赖容器 — 所有 Manager 通过 `@Environment(AppContainer.self)` 注入到 View。
/// 无第三方 DI 框架。
@MainActor
@Observable
final class AppContainer {

    // 持久化
    let profileRepo: ProfileRepository
    let settingsRepo: SettingsRepository

    // 基础设施
    let sshConfigProvider: SSHConfigProviding
    let portChecker: PortChecking
    let processManager: SSHProcessManaging
    let validator: ProfileValidator
    let logStore: TunnelLogStore

    // 应用层服务
    let sshHostManager: SSHHostManager
    let tunnelManager: TunnelManager
    let reconnectController: ReconnectController
    let settingsManager: SettingsManager
    let notificationManager: NotificationManager
    let lifecycleManager: AppLifecycleManager

    private(set) var profiles: [Profile] = []

    init() {
        // 1. 构造 leaf dependencies
        let store = AtomicFileStore()

        let appSupport = AppPaths.applicationSupport
        let profilesURL = appSupport.appendingPathComponent("profiles.json")
        let backupsDir = appSupport.appendingPathComponent("backups")
        let settingsURL = appSupport.appendingPathComponent("settings.json")

        let profileRepo = JSONProfileRepository(
            fileURL: profilesURL,
            backupDirectory: backupsDir,
            maxBackups: 10,
            store: store
        )
        let settingsRepo = JSONSettingsRepository(fileURL: settingsURL, store: store)

        let portChecker = TCPPortChecker()
        let validator = ProfileValidator()
        let logStore = TunnelLogStore()
        let processManager = SSHProcessManager()

        // 2. Application services
        let sshHostManager = SSHHostManager(
            provider: SSHConfigService(),
            defaultConfigPath: "~/.ssh/config"
        )
        let tunnelManager = TunnelManager(
            processManager: processManager,
            portChecker: portChecker,
            validator: validator,
            logStore: logStore
        )
        let reconnectController = ReconnectController()
        let settingsManager = SettingsManager(repository: settingsRepo)
        let notificationManager = NotificationManager()

        // 3. Lifecycle
        let lifecycleManager = AppLifecycleManager(
            tunnelManager: tunnelManager,
            reconnectController: reconnectController,
            settingsManager: settingsManager
        )

        // 4. 赋值给 self
        self.profileRepo = profileRepo
        self.settingsRepo = settingsRepo
        self.sshConfigProvider = sshHostManager.provider
        self.portChecker = portChecker
        self.processManager = processManager
        self.validator = validator
        self.logStore = logStore
        self.sshHostManager = sshHostManager
        self.tunnelManager = tunnelManager
        self.reconnectController = reconnectController
        self.settingsManager = settingsManager
        self.notificationManager = notificationManager
        self.lifecycleManager = lifecycleManager
    }

    static func bootstrap() -> AppContainer {
        let container = AppContainer()
        Task { await container.bootstrap() }
        return container
    }

    func bootstrap() async {
        // 加载 profiles
        do {
            profiles = try await profileRepo.load()
        } catch RepositoryError.fileNotFound {
            profiles = []  // 首次启动
        } catch {
            print("[Janus] Failed to load profiles: \(error)")
            profiles = []
        }

        // 加载 settings
        await settingsManager.load()

        // 注册所有 profile
        for profile in profiles {
            tunnelManager.registerProfile(profile)
        }

        // 启动 lifecycle
        lifecycleManager.start()

        // 刷新 SSH hosts
        await sshHostManager.refresh()
    }

    func upsertProfile(_ profile: Profile) async {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        tunnelManager.registerProfile(profile)
        try? await profileRepo.save(profiles)
    }

    func deleteProfile(_ id: UUID) async {
        profiles.removeAll { $0.id == id }
        tunnelManager.unregisterProfile(id: id)
        try? await profileRepo.save(profiles)
    }
}

/// App 文件路径工具
enum AppPaths {
    static var applicationSupport: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("com.lshgdut.janus-ssh", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
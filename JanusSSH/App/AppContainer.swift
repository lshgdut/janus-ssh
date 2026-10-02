import SwiftUI
import Observation
import JanusSSHTunnelEngine

/// 依赖容器 — 所有 Manager 通过 `@Environment(AppContainer.self)` 注入到 View。
/// 无第三方 DI 框架。
///
/// Task 7 状态:这是**最小可行迁移**。Engine 层已经走 ServicesContainer
/// (DAO + 协议化服务聚合),但 App 这一层仍保留 `tunnelManager` /
/// `sshHostManager` / `settingsManager` 等老 manager 的 API,以便既有 View
/// 代码不需要改动。
///
/// 后续清理(独立 PR):
/// - 删 SSHHostManager / SettingsManager,View 切到 `services.sshConfigManager`
///   / `services.settingsService`
/// - 删 TunnelManager / ReconnectController,AppContainer 切到
///   `services.tunnelService` / `services.reconnectService`
/// - 删 JSONProfileRepository / JSONSettingsRepository / ManagedPIDStore
///   / AtomicFileStore(老 init),仅用新 DAO 协议
@MainActor
@Observable
final class AppContainer {

    // MARK: - 新架构 (engine ServicesContainer) — 已有,留作后续迁移的接入点

    /// 新架构根 — 当前所有 View 暂未消费,Task 后续清理时统一切换
    let services: ServicesContainer

    // MARK: - 持久化(老 API — 保留)

    let profileRepo: ProfileRepository
    let settingsRepo: SettingsRepository
    let pidStore: ManagedPIDStore

    // MARK: - 基础设施

    let sshConfigProvider: SSHConfigProviding
    let portChecker: PortChecking
    let processManager: SSHProcessManaging
    let validator: ProfileValidator
    let logStore: TunnelLogStore

    // MARK: - 应用层服务(老 API — 保留)

    let sshHostManager: SSHHostManager
    let tunnelManager: TunnelManager
    let reconnectController: ReconnectController
    let settingsManager: SettingsManager
    let notificationManager: NotificationManager
    let lifecycleManager: AppLifecycleManager
    let themeController: ThemeController

    private(set) var profiles: [Profile] = []

    init() {
        // 1. 构造 leaf dependencies
        let store = AtomicFileStore()

        let appSupport = AppPaths.applicationSupport
        let profilesURL = appSupport.appendingPathComponent("profiles.json")
        let backupsDir = appSupport.appendingPathComponent("backups")
        let settingsURL = appSupport.appendingPathComponent("settings.json")
        let pidStoreURL = appSupport.appendingPathComponent("managed_pids.json")

        // 新 DAO(已在 Task 2 引入;后续会替换 profileRepo / settingsRepo / pidStore)
        let profileDAO = JSONProfileDAOImpl(store: store, directory: profilesURL)
        let settingsDAO = JSONSettingsDAOImpl(store: store, directory: settingsURL)
        let managedPIDDAO = JSONManagedPIDDAOImpl(store: store, directory: pidStoreURL)

        // 老 repositories(保留给老 managers)
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

        let pidStore = ManagedPIDStore(fileURL: pidStoreURL)

        // 2. 构造 ServicesContainer(Task 1-6 已就绪)
        let services = ServicesContainer(
            profileDAO: profileDAO,
            settingsDAO: settingsDAO,
            managedPIDDAO: managedPIDDAO
        )

        // 3. Application services(老 managers — 暂保留)
        let sshConfigProvider = SSHConfigService()
        let sshHostManager = SSHHostManager(
            provider: sshConfigProvider,
            defaultConfigPath: "~/.ssh/config"
        )
        let tunnelManager = TunnelManager(
            processManager: processManager,
            portChecker: portChecker,
            validator: validator,
            logStore: logStore,
            sshConfigProvider: sshHostManager.provider,
            pidStore: pidStore
        )
        let reconnectController = ReconnectController()
        let settingsManager = SettingsManager(repository: settingsRepo)
        let notificationManager = NotificationManager()

        // 4. Lifecycle
        let lifecycleManager = AppLifecycleManager(
            tunnelManager: tunnelManager,
            reconnectController: reconnectController,
            settingsManager: settingsManager
        )

        // 5. 主题
        let themeController = ThemeController(settingsManager: settingsManager)

        // 6. 赋值
        self.services = services
        self.profileRepo = profileRepo
        self.settingsRepo = settingsRepo
        self.pidStore = pidStore
        self.sshConfigProvider = sshConfigProvider
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
        self.themeController = themeController
    }

    static func bootstrap() -> AppContainer {
        let container = AppContainer()
        Task { await container.bootstrap() }
        return container
    }

    func bootstrap() async {
        // 启动 ServicesContainer(加载 profiles / settings 到 service 层)
        try? await services.bootstrap()

        // Sweep 上次会话残留的 SSH 子进程
        if let mpid = services.managedPIDService {
            _ = try? await mpid.sweepOrphans()
        }

        // 老 manager 自己的 bootstrap(profiles / settings 加载)
        do {
            profiles = try await profileRepo.load()
        } catch RepositoryError.fileNotFound {
            profiles = []
        } catch {
            print("[Janus] Failed to load profiles: \(error)")
            profiles = []
        }

        await settingsManager.load()

        // 启动主题监听
        themeController.start()

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

        // 同步到新 ProfileService
        try? await services.profileService?.update(profile)
    }

    func deleteProfile(_ id: UUID) async {
        profiles.removeAll { $0.id == id }
        tunnelManager.unregisterProfile(id: id)
        try? await profileRepo.save(profiles)

        try? await services.profileService?.delete(id: id)
    }

    // MARK: - Editor window

    private(set) var editingProfile: Profile?
    private(set) var editingProfileIsNew: Bool = false
    private var inFlightDuplicateNames: Set<String> = []

    func requestEdit(profile: Profile, isNew: Bool = false) {
        editingProfile = profile
        editingProfileIsNew = isNew
    }

    func closeEditor() {
        if editingProfileIsNew, let name = editingProfile?.name {
            inFlightDuplicateNames.remove(name)
        }
        editingProfile = nil
        editingProfileIsNew = false
    }

    func duplicateProfile(_ source: Profile) {
        var taken = Set(profiles.map(\.name))
        taken.subtract([source.name])
        taken.formUnion(inFlightDuplicateNames)
        let copy = source.duplicated(takenNames: taken)
        inFlightDuplicateNames.insert(copy.name)
        requestEdit(profile: copy, isNew: true)
    }

    func makeBlankDraftProfile() -> Profile {
        Profile(
            name: "",
            sshHostAlias: sshHostManager.hosts.first?.alias ?? "",
            forwards: [PortForward(localHost: "127.0.0.1", localPort: 0,
                                   remoteHost: "127.0.0.1", remotePort: 0, label: nil)],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Preview seed
    #if DEBUG
    func seedPreviewProfiles() {
        let now = Date()
        let prod = Profile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Production",
            sshHostAlias: "production",
            forwards: [
                PortForward(localHost: "127.0.0.1", localPort: 15432,
                             remoteHost: "10.20.0.15", remotePort: 5432, label: "postgres"),
                PortForward(localHost: "127.0.0.1", localPort: 16379,
                             remoteHost: "10.20.0.16", remotePort: 6379, label: "redis"),
                PortForward(localHost: "127.0.0.1", localPort: 18080,
                             remoteHost: "10.20.0.17", remotePort: 8080, label: "http"),
            ],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: now, updatedAt: now
        )
        let staging = Profile(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Staging",
            sshHostAlias: "staging",
            forwards: [
                PortForward(localHost: "127.0.0.1", localPort: 25432,
                             remoteHost: "10.30.0.15", remotePort: 5432, label: nil),
                PortForward(localHost: "127.0.0.1", localPort: 28080,
                             remoteHost: "10.30.0.17", remotePort: 8080, label: nil),
            ],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: now, updatedAt: now
        )
        let priv = Profile(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Private Server",
            sshHostAlias: "bastion",
            forwards: [
                PortForward(localHost: "127.0.0.1", localPort: 2222,
                             remoteHost: "192.168.1.10", remotePort: 22, label: "ssh"),
            ],
            behavior: Profile.Behavior(enabled: true, autoReconnect: false, autoStart: false),
            createdAt: now, updatedAt: now
        )
        profiles = [prod, staging, priv]
        for p in profiles {
            tunnelManager.registerProfile(p)
        }
    }
    #endif
}

#if DEBUG
extension AppContainer {
    /// Preview / Live Preview 用的 stub container,不读盘、不 sweep 孤儿进程。
    @MainActor
    static var preview: AppContainer {
        let c = AppContainer()
        c.seedPreviewProfiles()
        let prodID    = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let stagingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let privID    = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        c.tunnelManager._previewSetState(
            profileID: prodID,
            state: .running,
            startedAt: Date().addingTimeInterval(-2 * 3600 - 14 * 60)
        )
        c.tunnelManager._previewSetState(
            profileID: stagingID,
            state: .running,
            startedAt: Date().addingTimeInterval(-3600 - 3 * 60)
        )
        c.tunnelManager._previewSetState(
            profileID: privID,
            state: .error,
            lastError: .networkUnreachable(host: "bastion")
        )
        return c
    }
}
#endif

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

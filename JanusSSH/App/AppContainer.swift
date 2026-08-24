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

    // SSH 子进程 PID 持久化 — 用于 App 重启后 sweep 孤儿进程
    let pidStore: ManagedPIDStore

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
    let themeController: ThemeController

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

        // 持久化 SSH 子进程 PID 列表 — 用来在 App 重启时 sweep 上一会话残留的孤儿
        let pidStoreURL = appSupport.appendingPathComponent("managed_pids.json")
        let pidStore = ManagedPIDStore(fileURL: pidStoreURL)

        // 2. Application services
        let sshHostManager = SSHHostManager(
            provider: SSHConfigService(),
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

        // 3. Lifecycle
        let lifecycleManager = AppLifecycleManager(
            tunnelManager: tunnelManager,
            reconnectController: reconnectController,
            settingsManager: settingsManager
        )

        // 4. 主题 — 在 settingsManager 之后构造,因为要订阅它
        let themeController = ThemeController(settingsManager: settingsManager)

        // 5. 赋值给 self
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
        self.themeController = themeController
        self.pidStore = pidStore
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

        // 启动主题监听 — 必须在 settings 加载后,否则读不到用户偏好
        themeController.start()

        // Sweep 上次会话残留的 SSH 子进程 — 必须在 registerProfile / start 之前
        // 否则会出现"App 还在 sweep,但用户先点 Start,端口已被本会话的旧 SSH 占住"的竞态
        await pidStore.load()
        let killed = await pidStore.sweep()
        if !killed.isEmpty {
            print("[Janus] Swept \(killed.count) orphan SSH process(es) from previous session")
        }

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

    // MARK: - Editor window

    /// 当前正在编辑的 profile(独立 window 用)
    private(set) var editingProfile: Profile?

    /// 区分"新建"vs"编辑"已有 profile — ProfileEditorView 据此隐藏
    /// Delete / Save&Stop / Save&Restart 等只对已存在 profile 有意义的操作。
    private(set) var editingProfileIsNew: Bool = false

    /// 从 ProfileListView / EmptyState / 新建菜单调用
    /// 设置后会通过 @Observable 通知 ProfileEditorWindow scene 打开
    func requestEdit(profile: Profile, isNew: Bool = false) {
        editingProfile = profile
        editingProfileIsNew = isNew
    }

    func closeEditor() {
        editingProfile = nil
        editingProfileIsNew = false
    }

    /// 构造一份空白 Profile,作为"新建"的初始值。
    /// 三个调用点(RootView / ProfileListView.Toolbar / ProfileListView.EmptyState)
    /// 之前各写一份相同 8 行 factory,改一处容易漏改。集中到这里后,
    /// 未来给 Profile 加字段或调整默认值只改一处。
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

    func deleteProfile(_ id: UUID) async {
        profiles.removeAll { $0.id == id }
        tunnelManager.unregisterProfile(id: id)
        try? await profileRepo.save(profiles)
    }

    // MARK: - Preview seed
    #if DEBUG
    /// 给 SwiftUI Preview / Live Preview 用的种子数据入口。
    /// 在类内可写 `profiles`,从外部用 extension 调用。
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
    /// seed 3 个 mock profile,分别 mock running / running / error 三种状态,
    /// 让 Preview 能看到全状态的 ProfileCard 视觉。
    @MainActor
    static var preview: AppContainer {
        let c = AppContainer()
        c.seedPreviewProfiles()
        // mock 状态 — 让 Preview 看到不同 TunnelState 的渲染效果
        let prodID    = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let stagingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let privID    = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        c.tunnelManager._previewSetState(
            profileID: prodID,
            state: .running,
            startedAt: Date().addingTimeInterval(-2 * 3600 - 14 * 60)  // 2h 14m ago
        )
        c.tunnelManager._previewSetState(
            profileID: stagingID,
            state: .running,
            startedAt: Date().addingTimeInterval(-3600 - 3 * 60)  // 1h 03m ago
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
import Foundation

/// Services 容器,持有 DAO 引用 + 构造应用层服务实例。
///
/// 用途: 在 AppContainer 启动时一次性 wire 好 DAO + service,把"协议 + 实现"
/// 解耦推到这一层。后续任务会给 container 加 settingsService、
/// managedPIDService 等。
///
/// 为什么是 `@MainActor final class` 而不是 `actor`:
/// - brief 原方案是 `actor ServicesContainer` + `MainActor.run` 桥接
///   `ProfileServiceImpl`(@MainActor)的 init / bootstrap。
/// - Swift 6 strict concurrency 下,从 `MainActor.run` 闭包里回写
///   `actor` 上的 `var` 字段需要跨 actor 写,在 actor 边界上没有 await
///   入口会触发数据竞争警告。
/// - 改为 `@MainActor final class` 后,`ProfileServiceImpl` 的
///   `@MainActor` init 和 `bootstrap()` 都在同一隔离域,不需要跨 actor 桥接,
///   也不需要 `MainActor.run`。brief 已授权这个 fallback:
///   "If MainActor.run produces Swift 6 warnings, consider an alternative
///    pattern: make ServicesContainer itself @MainActor (then it's not an
///    actor — it's a final class). The brief's actor-based version is fine
///    if it compiles."
///
/// 后续任务(Task 4+) 可以在这个 container 上加更多 `@MainActor` 服务 slot
/// (settingsService / managedPIDService / etc.),不会破坏现有的 wire 形式。
@MainActor
public final class ServicesContainer {

    // MARK: - DAOs (single source of truth)

    public let profileDAO: ProfileDAO
    public let settingsDAO: SettingsDAO
    public let managedPIDDAO: ManagedPIDDAO

    // MARK: - Services (filled in by bootstrap)

    public private(set) var profileService: ProfileService?

    // MARK: - Init

    public init(
        profileDAO: ProfileDAO,
        settingsDAO: SettingsDAO,
        managedPIDDAO: ManagedPIDDAO
    ) {
        self.profileDAO = profileDAO
        self.settingsDAO = settingsDAO
        self.managedPIDDAO = managedPIDDAO
    }

    // MARK: - Bootstrap

    /// 构造 + 装载所有服务,并加载初始数据。
    /// 调用方在 AppContainer(@MainActor) 的 init 完成后立刻调用。
    public func bootstrap() async throws {
        let service = ProfileServiceImpl(dao: profileDAO)
        try await service.bootstrap()
        self.profileService = service
    }
}
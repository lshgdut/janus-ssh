import Foundation

/// Settings 应用层服务 — 在 `SettingsDAO` 之上封装业务用例(load / update)。
///
/// 设计要点:
/// - `@MainActor @Observable`:UI 视图通过 `@Bindable` / 直接属性访问观察
///   `settings`,任何修改都会自动触发 SwiftUI 重新渲染。
/// - `@MainActor` 保证 service 上的 `settings` 与其他 ViewModel 的并发
///   读写都在同一个隔离域里,避免数据竞争。
/// - DAO 是 `actor`,跨隔离域的调用自然 await,不破坏 Swift 6 strict concurrency。
/// - `update(_:)` 的 diff-then-write 早返回堵死了"MenuBarExtra(isInserted:)
///   ↔ NSStatusItem overflow"触发的 ~150 Hz setter 风暴 — 即便 setter 被
///   连续调 N 次,只要值没变就不再触发 @Observable change、不再 spawn 写盘
///   Task,不再跑 JSON encode + fsync + rename。
@MainActor
public protocol SettingsService: AnyObject, Sendable {
    var settings: AppSettings { get }
    func update(_ mutation: (inout AppSettings) -> Void) async throws
}

@MainActor
@Observable
public final class SettingsServiceImpl: SettingsService {
    public private(set) var settings: AppSettings = .defaults

    private let dao: SettingsDAO

    public init(dao: SettingsDAO) {
        self.dao = dao
    }

    public func bootstrap() async throws {
        settings = try await dao.load()
    }

    public func update(_ mutation: (inout AppSettings) -> Void) async throws {
        var next = settings
        mutation(&next)
        guard next != settings else { return }
        try await dao.save(next)
        settings = next
    }
}

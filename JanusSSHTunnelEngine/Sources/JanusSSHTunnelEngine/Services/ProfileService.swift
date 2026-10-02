import Foundation

/// Profile 应用层服务 — 在 `ProfileDAO` 之上封装业务用例
/// (create / update / delete / duplicate / validate)。
///
/// 设计要点:
/// - `@MainActor @Observable`:UI 视图通过 `@Bindable` / 直接属性访问观察
///   `profiles`,任何修改都会自动触发 SwiftUI 重新渲染。
/// - `@MainActor` 保证 service 上的 `profiles` 数组与其他 ViewModel 的并发
///   读写都在同一个隔离域里,避免数据竞争。
/// - DAO 是 `actor`,跨隔离域的调用自然 await,不破坏 Swift 6 strict concurrency。
/// - `validate(_:)` 委托给 `ProfileValidator`(单参数版本 — persistence 层
///   校验,只检查 name 非空;Editor 校验走 `validate(_:knownHosts:)`)。
@MainActor
public protocol ProfileService: AnyObject, Sendable {
    var profiles: [Profile] { get }
    func create(name: String, sshHostAlias: String, forwards: [PortForward], behavior: Profile.Behavior) async throws -> Profile
    func update(_ profile: Profile) async throws
    func delete(id: UUID) async throws
    func duplicate(id: UUID, name: String?) async throws -> Profile
    func validate(_ profile: Profile) async throws -> [ValidationIssue]
}

@MainActor
@Observable
public final class ProfileServiceImpl: ProfileService {
    public private(set) var profiles: [Profile] = []

    private let dao: ProfileDAO
    private let validator: ProfileValidator

    public init(dao: ProfileDAO, validator: ProfileValidator = ProfileValidator()) {
        self.dao = dao
        self.validator = validator
    }

    public func bootstrap() async throws {
        profiles = try await dao.loadAll()
    }

    public func create(
        name: String,
        sshHostAlias: String,
        forwards: [PortForward],
        behavior: Profile.Behavior
    ) async throws -> Profile {
        let profile = Profile(
            name: name,
            sshHostAlias: sshHostAlias,
            forwards: forwards,
            behavior: behavior
        )
        try await persist(profile)
        return profile
    }

    public func update(_ profile: Profile) async throws {
        try await persist(profile)
    }

    public func delete(id: UUID) async throws {
        guard profiles.contains(where: { $0.id == id }) else {
            throw AppError.profileNotFound(id: id)
        }
        try await dao.delete(id: id)
        profiles.removeAll { $0.id == id }
    }

    public func duplicate(id: UUID, name: String?) async throws -> Profile {
        guard let original = profiles.first(where: { $0.id == id }) else {
            throw AppError.profileNotFound(id: id)
        }
        let takenNames = Set(profiles.map(\.name))

        if let customName = name {
            // 显式名字: 用 ensureUnique 保证不冲突
            let now = Date()
            let copy = Profile(
                id: UUID(),
                name: ensureUnique(baseName: customName, taken: takenNames),
                sshHostAlias: original.sshHostAlias,
                forwards: original.forwards,
                behavior: original.behavior,
                createdAt: now,
                updatedAt: now
            )
            try await persist(copy)
            return copy
        }

        // 自动命名: 用 Profile.duplicated(takenNames:) —— 它会自动追加
        // " Copy" / " Copy 2" / ... 后缀,Finder 风格不补洞。
        let copy = original.duplicated(takenNames: takenNames)
        try await persist(copy)
        return copy
    }

    public func validate(_ profile: Profile) async throws -> [ValidationIssue] {
        validator.validate(profile)
    }

    private func persist(_ profile: Profile) async throws {
        let issues = validator.validate(profile)
        if !issues.isEmpty {
            throw AppError.validation(issues: issues)
        }
        if try await dao.exists(name: profile.name, excluding: profile.id) {
            throw AppError.duplicateProfileName(name: profile.name)
        }
        try await dao.upsert(profile)
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
    }

    /// 找最小可用名字 — 不补洞,直接递增找最小未占用的数字。
    /// 与 `Profile.duplicated(takenNames:)` 行为对齐(macOS Finder 风格)。
    private func ensureUnique(baseName: String, taken: Set<String>) -> String {
        if !taken.contains(baseName) { return baseName }
        var counter = 2
        while taken.contains("\(baseName) \(counter)") { counter += 1 }
        return "\(baseName) \(counter)"
    }
}
# ADR-0012: Unified `AppError`

## Status

Accepted · 2026-10-02

## Context

v0.3.x 的错误处理是分散的:

1. `TunnelError` 是 11 个 case 的 enum,但只覆盖 tunnel 相关错误
2. `SSHConfigError`(3 个 case)、`SSHProcessError`、`RepositoryError`、`ValidationIssue`、`TunnelError` 各自定义
3. View 层到处 `catch let error as TunnelError` + `catch let error as SSHConfigError` + `catch { error.localizedDescription }`,错误来源混杂
4. 跨域错误无法用类型表达(例:`profileNotFound` + `decode failure` + `lockUnavailable` 同时发生)

`cc-switch` 用单个 `thiserror` 生成的 `AppError` enum + 关联值,所有 service 返回 `Result<T, AppError>`。

## Decision

引入单一 `enum AppError: Error, Sendable, Equatable, LocalizedError`:

```swift
enum AppError: Error, Sendable, Equatable, LocalizedError {
    // 业务
    case profileNotFound(id: UUID)
    case duplicateProfileName(name: String)
    case crossProfileLocalPortConflict(port: UInt16, ownerProfileID: UUID)
    case sshHostUnknown(alias: String)
    case sshConfigResolutionFailed(alias: String, reason: String)
    case authenticationFailed(alias: String)
    case networkUnreachable(alias: String, reason: String)

    // 生命周期
    case sshBinaryNotFound
    case sshSpawnFailed(underlying: String)
    case sshExited(code: Int32?, signal: Int32?, reason: TerminationReason)

    // 持久化
    case io(path: String, source: String)
    case decode(path: String, source: String)
    case encode(path: String, source: String)
    case schemaVersionTooNew(found: Int, supported: Int)
    case schemaVersionTooOld(found: Int, supported: Int)
    case backupFailed(path: String, source: String)
    case lockUnavailable(resource: String)

    // 验证
    case validation(issues: [ValidationIssue])
}
```

约束:
- 所有 service 方法 `throws AppError` —— 不抛 `String`、不抛 `any Error` 渗漏
- `AppError` 必须 `Sendable`(跨 actor)、`Equatable`(测试断言)、`LocalizedError`(UI 文案)
- 关联值必须是 Sendable 类型(`UUID` / `String` / `UInt16` / `Int32?` / `TerminationReason` / `[ValidationIssue]`)

## Rationale

**统一错误类型让 View 层简单:** `catch let error as AppError` 一处搞定,switch 按 case 出 UI 文案。

**`Equatable` 让 log 去重:** `TunnelLogStore` 可以用 `if lastError != newError` 跳过重复写入。

**`Sendable` 是 Swift 6 strict concurrency 的硬要求:** 跨 actor 边界传错误必须 Sendable。

**`[ValidationIssue]` 关联值:** 一个 case 携带多条问题,而不是 N 个 `case validationName / validationHost / validationPort` 分散 case。

## Consequences

**好的:**
- 所有 service 签名 `throws AppError`(后续 task 会统一,tunnel-specific case 还在过渡)
- 测试可以 `XCTAssertEqual(error, .profileNotFound(id: x))`
- UI 文案集中在 `errorDescription` 一个 switch 里

**代价:**
- 现有 `TunnelError` 11 个 case 还在过渡期(Task 7 没删,TunnelService 仍 throw TunnelError)—— 后续清理时合并 `.duplicateLocalPort` / `.localPortUnavailable` 到 AppError
- `errorDescription` 文案现在用英文,后续接 Localizable.strings 时切换到 `LocalizedStringResource`

**回退:**
- AppError 是纯增量的,可以保留老的 TunnelError,新代码用 AppError 即可

# ADR-0013: Declarative Schema Migration via `JSONMigrator`

## Status

Accepted · 2026-10-02

## Context

v0.3.x 的 `SchemaVersion` 是个简单的 envelope(只标 version 字段),启动时:

1. decode envelope
2. `if version > current { throw }`
3. 失败 = `.decode error` 兜底

升级到新 envelope 字段需要手写 "decode → mutate → re-encode" 的胶水代码,且每个 JSON 文件(profile / settings / managed_pids)的迁移逻辑散落各处,容易漏。

`cc-switch` 用 SQLite + `user_version` PRAGMA + 声明式 `apply_schema_migrations()`,每个 migration 是一个 `(from_version, to_version, sql_ddl)` 元组,顺序执行。

## Decision

保留 JSON 文件(用户已确认不上 SQLite)。引入 `actor JSONMigrator`,带声明式 `(from, to, transform)` 链:

```swift
public actor JSONMigrator {
    public struct Transformation: Sendable {
        public let from: SchemaVersion
        public let to: SchemaVersion
        public let transform: @Sendable (Data) throws -> Data
    }

    public static let transformations: [Transformation] = [
        // 未来新增 v2 时:
        // Transformation(from: .v1, to: .v2) { data in
        //     // decode → 加新字段 → re-encode
        // }
    ]

    public func migrate(envelope: Data) throws -> Data {
        let current = try Self.decodeVersion(envelope)
        guard current <= supportedVersion else {
            throw AppError.schemaVersionTooNew(...)
        }
        var data = envelope
        for t in Self.transformations where t.from == current {
            data = try t.transform(data)
            // 校验 transform 后 version 已 bump
        }
        return data
    }
}
```

约束:
- 启动顺序: `read envelope → JSONMigrator.migrate(envelope) → 写入新 envelope(version = current)`
- 启动前 `AtomicFileStore` 已经在 `backups/` 留 10 个滚动备份,schema 不匹配时优先从 backup 恢复
- 失败 → 抛 `AppError.schemaVersionTooNew` / `.schemaVersionTooOld`,UI 弹"恢复失败"对话框

## Rationale

**声明式胜于命令式:** 新增字段 = 在 `transformations` 数组里加一项,不用改 migrate() 主体。

**actor 隔离:** `migrate()` 可能耗时,actor 让它在后台跑不影响 UI。

**`@Sendable (Data) throws -> Data` 闭包:** `Transformation` 本身 Sendable,可以被 Swift 6 strict concurrency 通过。

**当前 `transformations: []` 是 YAGNI 友好的:** v1 → v1 不需要转换。等真正需要 v2 时再加。

## Consequences

**好的:**
- 新增 schema 字段不需要改 `migrate()` 主体,只需要加一项 Transformation
- 老 JSON 文件 v0.3.1 (SchemaVersion.v1) 在 v0.4.0 启动时被自动 migrate,用户无感知
- 失败错误有专门 case(`.schemaVersionTooNew` / `.schemaVersionTooOld`),UI 可定向处理

**代价:**
- 迁移失败不重试 —— 用户需要从 `backups/` 手动选最近一次成功的 envelope
- 跨文件的 migration 没法在单个 transaction 内做(每个文件独立 envelope)

**回退:**
- `JSONMigrator` 是独立 actor,关闭它就是回到老的 envelope decode + version check 逻辑

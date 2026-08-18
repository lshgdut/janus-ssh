# ADR-0003: Codable + JSON + Atomic Write

## Status

Accepted · 2026-08-18

## Context

Profile 数据需要持久化。选项:
- **JSON** + atomic write
- **SQLite** (GRDB /)
- **CoreData** / **SwiftData**
- **Plist**

## Decision

使用 **Codable + JSON + 临时文件 + atomic rename**。

文件位置:`~/Library/Application Support/com.lshgdut.janus-ssh/profiles.json`

## Rationale

Profile 数据量极小(几十到几百个)。JSON 完全够用。

```json
{
  "version": 1,
  "updatedAt": "2026-08-18T15:42:02Z",
  "profiles": [
    {
      "id": "5E5D...",
      "name": "Production",
      "sshHostAlias": "production",
      "forwards": [
        { "id": "F1", "localHost": "127.0.0.1", "localPort": 15432,
          "remoteHost": "10.20.0.15", "remotePort": 5432, "label": "postgres" }
      ],
      "behavior": { "enabled": true, "autoReconnect": true, "autoStart": true },
      "createdAt": "2026-08-01T10:00:00Z",
      "updatedAt": "2026-08-18T15:42:02Z"
    }
  ]
}
```

## Atomic Write Strategy

```
profiles.json.tmp  ← write
       ↓ fsync
profiles.json.bak  ← 旧版 rename
       ↓
profiles.json      ← tmp rename
       ↓
父目录 fsync
```

**保证**:即使 App 在写过程中 crash:
- 要么是旧版(完整)
- 要么是新版(完整)
- 永远不会有中间态损坏

## Versioning

`SchemaVersion` enum:
```swift
enum SchemaVersion: Int {
    case v1 = 1
}
```

缺 `version` 字段 → 视为 v1(向后兼容)。
未知 `version` → 拒绝(避免静默接受未来版本)。

## Backups

每次 save 创建 timestamped 备份:
```
backups/
├── profiles-2026-08-18T15-42-02-123Z.json
├── profiles-2026-08-17T18-11-44-456Z.json
└── ...
```

保留最近 **10 个**。恢复时直接把备份内容写入主文件(走 atomic)。

## Why Not SQLite

- 数据量小,JSON 完全够
- Codable 原生支持
- 可读,容易调试
- 不需要 query
- 容易迁移(写迁移函数即可)

## Consequences

### Positive
- 简单
- 可读 / 可 diff / 可手改
- 容易备份
- 容易迁移

### Negative
- 不支持复杂查询(不必要)
- 频繁写性能差(不必要,Profile 写不频繁)

## Related

- `Sources/JanusSSHTunnelEngine/Persistence/`
- ADR-0004: 1 Profile = 1 SSH Process
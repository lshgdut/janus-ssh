# ADR-0011: Command / Service / DAO Layering

## Status

Accepted · 2026-10-02

## Context

`janus-ssh` 在 v0.3.x 阶段形成了 `JanusSSH/Features/*` + `JanusSSHTunnelEngine/{Domain,Persistence,SSH,Tunnel,Network,Services}` 的三层结构,但仍有几个结构性问题:

1. `TunnelManager` 是 549 行的 actor,跨 SSH 进程管理 + 状态机 + 退避调度 + 孤儿扫描四个职责
2. `AppContainer` 直接持有 13 个 leaf / manager 实例,没有 service 聚合根
3. 持久化层不规整:`JSONProfileRepository` 是 actor,但 `TunnelManager` 直接持有;没有按聚合拆 DAO
4. 没有统一的 Service 协议 — AppContainer 持有的全部是具体类,测试只能通过 `#DEBUG` 注入 mock

`cc-switch`(Rust + Tauri, v3.20.4)的 Command / Service / DAO 分层模式提供了清晰的对齐方向。

## Decision

把 `JanusSSHTunnelEngine` 重构为四层:

```
Domain         — 数据结构 + 跨服务事件(无依赖)
Persistence    — DAO 协议 + actor 实现(原子写 + envelope + 迁移)
Services       — 业务逻辑(每个能力一个 Service protocol + Impl)
App            — AppContainer 持有 ServicesContainer 作为 service 聚合根
```

关键约束:
- DAO 永远是 `actor`,只 CRUD 持久化数据
- 状态发布型 Service 用 `@MainActor @Observable`(`ProfileService` / `TunnelService` / `SettingsService`)
- 纯逻辑型 Service 用 `actor`(`SSHConfigManager` / `ReconnectService` / `ManagedPIDService`)
- AppContainer 持有 `ServicesContainer`,Views 通过 `container.services.*Service` 访问
- 旧 `TunnelManager` / `SSHHostManager` / `SettingsManager` / `JSONProfileRepository` / `JSONSettingsRepository` / `ManagedPIDStore` / `ReconnectController` 作为 compat shim 保留,Task 后续清理时删除

## Rationale

**协议-first 而不是具体类:** 协议让测试可以注入 fake 实现,无需 `#DEBUG`-only 的 `setState` 旁路。cc-switch 的 commands/* → services/* → DAO 分层就是这个思想。

**Service 按能力拆分:** `TunnelManager` 跨 SSH 进程 + 状态机 + 退避调度 + 孤儿扫描 — 4 个职责。commit `2306d1a` 已经把 `markStopping/markStopped` 抽到 `Tunnel` struct,commit `0ddcac4` 修了 5 个 handle 泄漏。继续按这个方向推:把退避决策抽到 `ReconnectService`,把孤儿扫描抽到 `ManagedPIDService`,剩下的就是 `TunnelService` 的状态机本身。

**`ServicesContainer` 作为聚合根:** 跟 cc-switch 的 `AppState` 一样,所有 service 在容器里 wire 起来,避免 AppContainer 直接管理 13 个依赖。

**保留 compat shim 不一次性删除:** App 这一层有 7 个 view 文件 + 1 个 preview seed 全都用 `container.tunnelManager.xxx` / `container.sshHostManager.xxx` / `container.settingsManager.xxx`。一次性 sed + 删除会让 diff 暴增(700+ 行),回归风险高。分两步:Task 1-7 引入新架构、保留旧 API;后续独立 PR 做 sed 重命名 + 删除。

## Consequences

**好的:**
- 每个 service 单独可测,测试用 in-memory DAO fake
- 引入新 service 只需在 `ServicesContainer.bootstrap()` 加一行 wire
- App 端的 `AppContainer.bootstrap()` 缩成几行
- 新功能可以选「新路径」或「老路径」—— 新功能走 services,老代码继续走 manager 直到迁移完

**代价:**
- 短期内 `JanusSSHTunnelEngine` 代码量增加(新 service + 老的 compat shim)
- 两条并行路径(profileRepo vs ProfileDAO,tunnelManager vs TunnelService)需要维护,直到清理 PR 完成
- 重命名 / 删除清理 PR 需要单独排期

**回退:**
- 老的 JSONProfileRepository 等文件保留,可以直接 git revert Task 7 的 commit

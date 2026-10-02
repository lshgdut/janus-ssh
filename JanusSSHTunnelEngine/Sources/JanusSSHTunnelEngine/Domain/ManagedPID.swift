import Foundation

/// 持久化记录 App 启动过的 SSH 子进程 PID,用于:
/// 1. App 被 force-quit / crash 时,SSH 子进程变成孤儿继续运行,占用本地端口
/// 2. 下次 App 启动时扫描该列表,把还活着的进程全部 SIGKILL
///
/// 字段与既有 `ManagedPIDStore.Entry` 完全对齐 — Domain 层重组过程中
/// `profileID` 必须保留(`sweep` 仍按 profile 维度回写),`startedAt` 同义于
/// `recordedAt`,`exePath` 仍是可选(旧 JSON 文件没有这字段,Codable 用
/// `decodeIfPresent` 容忍)。
public struct ManagedPID: Codable, Equatable, Sendable, Hashable {
    public let profileID: UUID
    public let pid: Int32
    public let startedAt: Date
    /// 进程可执行文件路径 — 启动时通过 `proc_pidpath` 记录,sweep 时用来
    /// 验证 PID 没被 OS recycle 出去交给别的进程(否则 SIGKILL 会误杀
    /// 用户正在跑的 `ssh` 或别的同名进程)。旧 JSON 文件没有这字段,
    /// Codable 用 `decodeIfPresent` 容忍 — 这部分条目降级到"只查 liveness"。
    public let exePath: String?

    public init(
        profileID: UUID,
        pid: Int32,
        startedAt: Date,
        exePath: String? = nil
    ) {
        self.profileID = profileID
        self.pid = pid
        self.startedAt = startedAt
        self.exePath = exePath
    }

    // 自定义解码 — 让旧 managed_pids.json(没有 exePath 字段)能继续工作,
    // 缺字段时为 nil,sweep 时只对带 fingerprint 的条目做强校验。
    enum CodingKeys: String, CodingKey {
        case profileID, pid, startedAt, exePath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profileID  = try c.decode(UUID.self, forKey: .profileID)
        pid        = try c.decode(Int32.self, forKey: .pid)
        startedAt  = try c.decode(Date.self, forKey: .startedAt)
        exePath    = try c.decodeIfPresent(String.self, forKey: .exePath)
    }
}

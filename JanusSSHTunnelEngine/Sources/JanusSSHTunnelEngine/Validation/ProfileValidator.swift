import Foundation

/// Profile 校验器。
///
/// 强制原型 Editor 中的实时校验规则:
/// 1. name 非空
/// 2. sshHostAlias 在已知 hosts 内
/// 3. forwards ≥ 1
/// 4. 同 profile 内 localPort 不重复
/// 5. localPort 范围 1..65535
/// 6. localHost / remoteHost 非空
///
/// 跨 profile 校验需要单独的入口,因为需要传入"其他现存 profile"。
public struct ProfileValidator: Sendable {
    public init() {}

    /// 单 profile 内的字段校验。
    ///
    /// - Parameters:
    ///   - profile: 待校验的 profile
    ///   - knownHosts: 从 `~/.ssh/config` 发现的 host alias 集合
    public func validate(
        _ profile: Profile,
        knownHosts: Set<String>
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // 1. name
        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Profile name is required.",
                field: "name"
            ))
        }

        // 2. sshHostAlias
        // 空 set 表示调用方没有可用的 SSH config provider(例如 preview /
        // 运行时未注入 provider)。此时编辑器侧已保证 alias 合法,不能把
        // "未知"误判成"~/.ssh/config 中不存在该 host"。
        if !knownHosts.isEmpty && !knownHosts.contains(profile.sshHostAlias) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "SSH host '\(profile.sshHostAlias)' is not in ~/.ssh/config.",
                field: "sshHostAlias"
            ))
        }

        // 3. forwards ≥ 1
        if profile.forwards.isEmpty {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Profile must have at least 1 forward.",
                field: "forwards"
            ))
            return issues  // 没有 forward 时,后续逐行校验无意义
        }

        // 4 & 5 & 6. 逐行校验 + 重复 localPort 检测
        var seenPorts: [UInt16: Int] = [:]  // port → first 出现的位置
        for (index, forward) in profile.forwards.enumerated() {
            let lineField = "forwards[\(index)]"

            if forward.localHost.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Local host is required.",
                    field: "\(lineField).localHost"
                ))
            }

            if forward.remoteHost.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Remote host is required.",
                    field: "\(lineField).remoteHost"
                ))
            }

            if forward.localPort == 0 || forward.localPort > 65535 {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Local port must be in 1..65535.",
                    field: "\(lineField).localPort"
                ))
            }

            if let firstIdx = seenPorts[forward.localPort] {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Local Port \(forward.localPort) is duplicated (rows \(firstIdx) and \(index)).",
                    field: "\(lineField).localPort"
                ))
            } else {
                seenPorts[forward.localPort] = index
            }
        }

        return issues
    }

    /// 跨 profile 端口冲突校验。
    ///
    /// - Parameters:
    ///   - profile: 待校验的 profile(通常是新增或修改)
    ///   - existing: 所有现存 profile
    ///   - excluding: 当编辑现有 profile 时,排除自身 ID
    func validateForCrossProfileConflict(
        _ profile: Profile,
        against existing: [Profile],
        excluding: UUID?
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        let occupiedByPort: [UInt16: [UUID]] = existing
            .filter { $0.id != excluding }
            .reduce(into: [UInt16: [UUID]]()) { acc, p in
                for f in p.forwards {
                    acc[f.localPort, default: []].append(p.id)
                }
            }

        for forward in profile.forwards {
            if let conflicts = occupiedByPort[forward.localPort], !conflicts.isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Local Port \(forward.localPort) is already used by another profile.",
                    field: "forwards.localPort"
                ))
                // 只记录一次即可,不需要每个 forward 都报
                break
            }
        }

        return issues
    }
}
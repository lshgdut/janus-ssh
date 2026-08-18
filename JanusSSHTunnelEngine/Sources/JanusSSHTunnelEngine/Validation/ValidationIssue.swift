import Foundation

/// 校验问题的严重程度
enum ValidationSeverity: Sendable, Hashable {
    case error
    case warning
}

/// 单条校验结果
///
/// `field` 用点路径定位问题,例如:
/// - `"name"` — Profile 名称为空
/// - `"sshHostAlias"` — Host 不在已知列表
/// - `"forwards"` — 整体校验(如至少 1 条)
/// - `"forwards.localPort"` — 某一行 localPort 重复或越界
/// - `"forwards.localHost"` / `"forwards.remoteHost"` — 主机名空
struct ValidationIssue: Sendable, Hashable {
    let severity: ValidationSeverity
    let message: String
    let field: String?
}
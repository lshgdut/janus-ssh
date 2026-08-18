import Foundation

/// SSH config 解析器 — 简化版,只解析 host alias + 字段,语义交给 ssh -G。
///
/// 不重复实现 OpenSSH 语义 — 这是 ADR-0010 的原则。
struct SSHConfigParser {

    /// SSH config 一行一个 key/value
    enum Key: String, CaseIterable {
        case host, hostname, user, port
        case identityFile = "IdentityFile"
        case proxyJump = "ProxyJump"
        case forwardAgent = "ForwardAgent"
        case serverAliveInterval = "ServerAliveInterval"
        case include = "Include"
    }

    /// 解析后的一个 Host 段
    struct Entry {
        let alias: String
        var options: [Key: String]
    }

    /// 解析整个 config 文件内容
    static func parse(_ content: String, basePath: String? = nil) -> [Entry] {
        var entries: [Entry] = []
        var current: Entry?

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // 跳过注释 / 空行
            if line.isEmpty || line.hasPrefix("#") { continue }

            // 解析 key value(用第一个空白分隔)
            guard let spaceIdx = line.firstIndex(of: " ") else { continue }
            let key = String(line[..<spaceIdx])
            let value = String(line[line.index(after: spaceIdx)...])
                .trimmingCharacters(in: .whitespaces)

            guard let k = Key(rawValue: key) else { continue }

            if k == .host {
                // Host 行支持多个 alias(空格分隔),取第一个非通配的
                let alias = value.split(separator: " ").first.map(String.init) ?? value
                // 跳过通配 Host(原型的 SSH Hosts 页不显示通配)
                if alias.contains("*") || alias.contains("?") { continue }
                if let c = current { entries.append(c) }
                current = Entry(alias: alias, options: [:])
                continue
            }

            // Include 指令 — 暂不递归(交给后续扩展)
            if k == .include { continue }

            // 其他 key 写入当前段(取第一个)
            if current != nil, current?.options[k] == nil {
                current?.options[k] = value
            }
        }
        if let c = current { entries.append(c) }
        return entries
    }
}
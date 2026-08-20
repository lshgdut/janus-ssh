import Foundation

/// SSH config 解析器 — 对齐 OpenSSH 行为:
/// 1. `Include` 路径相对当前 config 所在目录(已 `~` 展开)
/// 2. `Include` 支持 glob 通配符(`*` / `?` / `[...]`)
/// 3. 多个 `Include` 可空格分隔在一行
/// 4. 防止循环引用(同一文件只 parse 一次)
/// 5. 通配 `Host *` 跳过,语义交给 ssh -G 解析
///
/// 不重复实现 OpenSSH 语义(除 Include 这种必要的)— 这是 ADR-0010 的原则。
public struct SSHConfigParser {
    public init() {}

    public enum Key: String, CaseIterable {
        case host = "Host"
        case hostname = "HostName"
        case user = "User"
        case port = "Port"
        case identityFile = "IdentityFile"
        case proxyJump = "ProxyJump"
        case forwardAgent = "ForwardAgent"
        case serverAliveInterval = "ServerAliveInterval"
        case include = "Include"
    }

    public struct Entry: Equatable {
        public let alias: String
        public var options: [Key: String]

        public init(alias: String, options: [Key: String]) {
            self.alias = alias
            self.options = options
        }
    }

    /// 解析入口(对外)
    public static func parse(_ content: String, basePath: String? = nil) -> [Entry] {
        var ctx = ParserContext(visited: [], visitedBase: nil)
        return parseRecursive(content: content, basePath: basePath, ctx: &ctx)
    }

    /// 文件存在时直接 parse,否则返回空
    public static func parseFile(at path: String) -> [Entry] {
        let expanded = (path as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            return []
        }
        return parse(content, basePath: expanded)
    }

    // MARK: - Internal recursive parser

    private struct ParserContext {
        /// 已访问的文件(绝对路径),防止循环
        var visited: Set<String>
        var visitedBase: String?

        init(visited: Set<String>, visitedBase: String?) {
            self.visited = visited
            self.visitedBase = visitedBase
        }
    }

    /// 递归解析。循环引用保护:每个绝对路径只 parse 一次。
    private static func parseRecursive(
        content: String,
        basePath: String?,
        ctx: inout ParserContext
    ) -> [Entry] {
        var entries: [Entry] = []
        var current: Entry?

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // key value(用第一个空白分隔,允许任意空格/tab)
            guard let spaceIdx = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let key = String(line[..<spaceIdx])
            let value = String(line[line.index(after: spaceIdx)...])
                .trimmingCharacters(in: .whitespaces)

            guard let k = Key(rawValue: key) else { continue }
            // SSH config 是大小写不敏感的(对齐 OpenSSH)
            // rawValue 已经精确匹配,无需二次处理

            if k == .host {
                let alias = value.split(separator: " ", omittingEmptySubsequences: true)
                    .first.map(String.init) ?? value
                // 通配 Host 跳过
                if alias.contains("*") || alias.contains("?") || alias.contains("[") { continue }
                if let c = current { entries.append(c) }
                current = Entry(alias: alias, options: [:])
                continue
            }

            if k == .include {
                guard let basePath = basePath else {
                    // 没有 basePath 无法解析 Include — 跳过
                    continue
                }
                let baseDir = (basePath as NSString).deletingLastPathComponent
                // Include 一行可空格分隔多个 glob
                let patterns = value.split(separator: " ", omittingEmptySubsequences: true)
                    .map(String.init)
                for pattern in patterns {
                    let expanded = (pattern as NSString).expandingTildeInPath
                    let globPath = (expanded as NSString).expandingTildeInPath
                    // glob 解析
                    let matches = expandGlob(pattern: globPath, in: baseDir)
                    for match in matches {
                        let resolved = resolvePath(match, baseDir: baseDir)
                        // 防循环:同一文件不解析第二次
                        let canonical = canonicalizePath(resolved)
                        if ctx.visited.contains(canonical) { continue }
                        ctx.visited.insert(canonical)

                        guard let includedContent = try? String(contentsOfFile: resolved, encoding: .utf8) else {
                            continue  // 找不到 → 跳过(对齐 OpenSSH 行为)
                        }
                        let sub = parseRecursive(
                            content: includedContent,
                            basePath: resolved,
                            ctx: &ctx
                        )
                        entries.append(contentsOf: sub)
                    }
                }
                continue
            }

            // 其他 key 写入当前段(取第一个)
            if current != nil, current?.options[k] == nil {
                current?.options[k] = value
            }
        }
        if let c = current { entries.append(c) }
        return entries
    }

    // MARK: - Path helpers

    /// 展开 glob 通配符到具体文件路径
    private static func expandGlob(pattern: String, in baseDir: String) -> [String] {
        let fm = FileManager.default
        // 先展开 ~
        let expanded = (pattern as NSString).expandingTildeInPath
        // 绝对路径:不展开 glob,直接判断存在
        if expanded.hasPrefix("/") {
            // 但还是要看是否有 glob 字符;如果没有直接返回
            if !expanded.contains("*") && !expanded.contains("?") {
                return fm.fileExists(atPath: expanded) ? [expanded] : []
            }
            // 绝对路径带 glob,分出 dir + pattern
            let url = URL(fileURLWithPath: expanded)
            let dir = url.deletingLastPathComponent().path
            let namePattern = url.lastPathComponent
            return matches(in: dir, pattern: namePattern)
        }
        // 相对路径
        // pattern 可能含 dir 部分 (e.g. "subdir/hosts-*.conf") — 先按 / 拆出
        let parts = pattern.split(separator: "/", maxSplits: 1)
        let relativeDir = parts.count == 2 ? String(parts[0]) : ""
        let fileName = parts.count == 2 ? String(parts[1]) : pattern
        let searchDir = relativeDir.isEmpty ? baseDir
            : (baseDir as NSString).appendingPathComponent(relativeDir)
        return matches(in: searchDir, pattern: fileName)
    }

    private static func matches(in dir: String, pattern: String) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let matched = contents.filter { fnmatch(pattern, fn: $0) }
        return matched.map { (dir as NSString).appendingPathComponent($0) }
    }

    /// 简易 glob 匹配 — 支持 `*` `?` `[abc]` (范围)
    /// 不完整实现 POSIX fnmatch,但覆盖 OpenSSH 常见场景
    private static func fnmatch(_ pattern: String, fn name: String) -> Bool {
        return matchHere(Array(pattern), Array(name), 0, 0)
    }

    private static func matchHere(_ p: [Character], _ s: [Character], _ pi: Int, _ si: Int) -> Bool {
        var i = pi, j = si
        while i < p.count {
            switch p[i] {
            case "*":
                // 跳过连续的 *
                while i + 1 < p.count && p[i+1] == "*" { i += 1 }
                if i + 1 == p.count { return true }
                // 尝试匹配任意位置
                while j <= s.count {
                    if matchHere(p, s, i+1, j) { return true }
                    j += 1
                }
                return false
            case "?":
                if j == s.count { return false }
                i += 1; j += 1
            case "[":
                // 字符类 [abc] 或 [a-z]
                if j == s.count { return false }
                i += 1
                var negate = false
                if i < p.count && p[i] == "!" { negate = true; i += 1 }
                var matched = false
                while i < p.count && p[i] != "]" {
                    if i + 2 < p.count && p[i+1] == "-" {
                        // range
                        if s[j] >= p[i] && s[j] <= p[i+2] { matched = true }
                        i += 3
                    } else {
                        if p[i] == s[j] { matched = true }
                        i += 1
                    }
                }
                if i >= p.count { return false }  // 没有闭合 ]
                i += 1  // 跳过 ]
                if matched == negate { return false }
                j += 1
            default:
                if j == s.count || p[i] != s[j] { return false }
                i += 1; j += 1
            }
        }
        return j == s.count
    }

    private static func resolvePath(_ path: String, baseDir: String) -> String {
        if path.hasPrefix("/") { return path }
        return (baseDir as NSString).appendingPathComponent(path)
    }

    /// 规范化路径(解析 ../, 去掉末尾 /)用于循环检测
    private static func canonicalizePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL.path
        return url
    }
}
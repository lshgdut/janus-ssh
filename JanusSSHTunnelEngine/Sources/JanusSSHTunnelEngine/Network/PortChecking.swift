import Foundation

/// 端口检查协议 — 抽象层让测试可以替换 mock
protocol PortChecking: Sendable {
    /// 返回 true 表示端口空闲(无人 LISTEN),false 表示已被占用
    func isPortAvailable(host: String, port: UInt16) async -> Bool
}

/// 默认实现 — 用 NWConnection 探测
/// 注意:这只是 preflight,真正判断仍然依赖 ssh -L 的 ExitOnForwardFailure 兜底
final class TCPPortChecker: PortChecking, @unchecked Sendable {
    func isPortAvailable(host: String, port: UInt16) async -> Bool {
        // 简化版:尝试 connect 一次,失败说明端口空闲
        // 生产代码应使用 NWConnection 并设置超时
        // 此处先用 socket 实现,TODO:替换为 Network.framework
        return await withCheckedContinuation { cont in
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                cont.resume(returning: true)  // 创建 socket 失败默认认为可用
                return
            }
            defer { close(fd) }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(port).bigEndian
            addr.sin_addr.s_addr = inet_addr(host)  // 仅支持 IPv4

            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            // connect 失败 = 没人 listen = 端口可用
            cont.resume(returning: result != 0)
        }
    }
}
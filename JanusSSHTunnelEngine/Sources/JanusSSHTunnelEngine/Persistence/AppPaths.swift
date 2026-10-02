import Foundation

/// 引擎层文件系统路径常量。
///
/// 单独的模块,跟 app 端 `AppContainer.AppPaths` 不冲突 — Swift 按模块
/// 命名空间解析,app 端继续引用自己的 `AppPaths`,DAO 通过
/// `JanusSSHTunnelEngine.AppPaths` 默认值取这里。
///
/// DAO 测试用 `AtomicFileStore(directory: tmpDir)` + 直接传
/// `directory:` 覆盖默认路径 — 生产路径 `applicationSupport` 只在
/// `AppContainer` 实际装配 DAO 时落到默认。
public enum AppPaths {
    /// `~/Library/Application Support/com.lshgdut.janus-ssh/`
    public static var applicationSupport: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("com.lshgdut.janus-ssh", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var profilesJSON: URL {
        applicationSupport.appendingPathComponent("profiles.json")
    }

    public static var settingsJSON: URL {
        applicationSupport.appendingPathComponent("settings.json")
    }

    public static var managedPidsJSON: URL {
        applicationSupport.appendingPathComponent("managed_pids.json")
    }
}

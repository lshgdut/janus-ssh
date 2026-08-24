import AppKit
import Observation
import JanusSSHTunnelEngine

/// 监听 `SettingsManager.state.general.theme`,把 App 的全局外观切到对应模式。
///
/// 为什么不用 SwiftUI 的 `.preferredColorScheme(...)`:
/// - 它只在 SwiftUI Scene 内部生效,Mac 的 menu bar / NSPopover 宿主不走 Scene,
///   这些会留在 system appearance,跟主窗口脱节,出现"主窗口是黑、菜单栏是亮"的割裂。
/// - 直接改 `NSApp.appearance` 是 AppKit 的统一入口,所有窗口 + 菜单栏 +
///   popover 一起切。
@MainActor
final class ThemeController {
    private let settingsManager: SettingsManager
    private var observerTask: Task<Void, Never>?
    private var lastApplied: AppSettings.Theme?

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    /// 启动监听 + 应用启动时的初始主题。App 启动时调一次。
    func start() {
        // 立刻应用一次 — 启动时 App 可能继承系统外观,如果不立即覆盖,
        // 用户在 Settings 里切到 Light/Dark 前看到的还是系统的样子。
        apply(settingsManager.state.general.theme)

        observerTask?.cancel()
        observerTask = Task { @MainActor [weak self] in
            // withObservationTracking 单次触发,所以包成循环等下一次变化
            while !Task.isCancelled {
                guard let self = self else { return }
                // 当前快照
                let current = self.settingsManager.state.general.theme
                // 等 theme 变化(onChange 回调触发)
                await self.waitForThemeChange()
                if Task.isCancelled { return }
                let next = self.settingsManager.state.general.theme
                if next != current {
                    self.apply(next)
                }
            }
        }
    }

    func stop() {
        observerTask?.cancel()
        observerTask = nil
    }

    deinit {
        // 非 isolated deinit,只走 Task.cancel (Sendable safe)。
        observerTask?.cancel()
    }

    // MARK: - Helpers

    /// 阻塞直到 SettingsManager 的 theme 字段被写入一次。
    /// `withObservationTracking` 的 onChange 只 fire 一次,所以外层用 while 循环复用。
    private func waitForThemeChange() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                // 读一次 theme 触发订阅
                _ = self.settingsManager.state.general.theme
            } onChange: {
                continuation.resume()
            }
        }
    }

    /// 把 AppKit 全局外观切到指定主题。
    /// `.system` 设为 nil — 跟着系统走,这是 macOS 默认行为。
    private func apply(_ theme: AppSettings.Theme) {
        guard theme != lastApplied else { return }
        lastApplied = theme
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
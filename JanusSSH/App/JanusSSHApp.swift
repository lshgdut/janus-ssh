import SwiftUI
import JanusSSHTunnelEngine

@main
struct JanusSSHApp: App {
    @State private var container: AppContainer
    @State private var menuBarController: MenuBarController?

    init() {
        let container = AppContainer.bootstrap()
        _container = State(initialValue: container)
        _menuBarController = State(initialValue: MenuBarController(container: container))
    }

    var body: some Scene {
        // 主窗口用 Window(单例)而不是 WindowGroup(多实例)
        // — WindowGroup 每次 openWindow(id:) 都会开新窗口,
        // 菜单栏点 "Open Application" 会越点越多。
        // Window 是 macOS 13+ 的 singleton scene,openWindow 会聚焦已有实例。
        Window("Janus SSH", id: "main") {
            MainWindowContent(container: container)
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear {
                    // App 启动时挂上 menu bar controller — 监听 showMenuBarIcon
                    // setting,真正实现 Settings 开关切换菜单栏图标可见性。
                    // SwiftUI MenuBarExtra 用 `if` 条件化包住会触发编译器崩溃
                    // (SceneBuilder 推断不出来),所以走 NSStatusItem。
                    menuBarController?.start()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Cmd+N — 弹出空 profile 的编辑器
            // 注意:命令菜单不能拿 openWindow,所以走 NotificationCenter → RootView → openWindow
            CommandGroup(replacing: .newItem) {
                Button("New Profile") {
                    NotificationCenter.default.post(name: .newProfileRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        // 独立 Profile Editor 窗口 — 避开 .sheet 的固定尺寸截断
        // 监听 container.editingProfile,非 nil 时显示
        WindowGroup("Edit Profile", id: "profile-editor") {
            ProfileEditorWindow()
                .environment(container)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 720)

        Settings {
            SettingsView()
                .environment(container)
                .frame(minWidth: 720, minHeight: 560)
        }
    }
}

/// 包裹主窗口内容,保证 RootView 拿到 AppContainer 的环境
private struct MainWindowContent: View {
    let container: AppContainer
    var body: some View {
        RootView()
            .environment(container)
    }
}

extension Notification.Name {
    static let newProfileRequested = Notification.Name("janus.newProfileRequested")
}

extension JanusSSHApp {
    /// 加载菜单栏图标 — 直接复用 AppIcon 资源,与 Dock 图标保证 100% 一致。
    /// 之前用 Core Graphics 重画 Janus 双弧,和真 PNG 渐变色 / 圆角细节会有细微差异。
    /// NSImage(named: "AppIcon") 由 asset catalog 提供,自带 macOS squircle 蒙版和
    /// 高分辨率渲染,@2x 实际 44×44 像素。
    fileprivate func makeMenuBarIcon() -> NSImage {
        // AppIcon 是 asset catalog 里的应用图标名
        let image = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage ?? NSImage()
        // 菜单栏图标推荐 18-22pt,实际渲染大小 @2x 是 36-44 像素
        image.size = NSSize(width: 22, height: 22)
        return image
    }
}

// MARK: - MenuBarController
// 用 NSStatusItem 而不是 SwiftUI MenuBarExtra — 后者不支持运行时切换可见性,
// 而 Settings 里 "Show Menu Bar Icon" 需要能真正隐藏图标。
// SwiftUI MenuBarExtra 用 `if` 条件包住会触发 SceneBuilder 类型推断失败
// ("failed to produce diagnostic"),所以走 AppKit。

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let container: AppContainer
    private var visibilityTask: Task<Void, Never>?
    private var popover: NSPopover?
    private var outsideClickMonitor: Any?

    init(container: AppContainer) {
        self.container = container
    }

    deinit {
        // 非 isolated deinit,只能安全访问 Sendable 值
        // 实际清理走 visibilityTask.cancel() — Task.cancel 是 Sendable safe
        visibilityTask?.cancel()
    }

    /// App 退出时主动调用 — 同步移除 NSStatusItem
    /// 不能在 deinit 里调 NSStatusBar.system(非 Sendable + 非 main-actor safe)
    func shutdown() {
        visibilityTask?.cancel()
        removeOutsideClickMonitor()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 必须显式设 image.size — AppIcon intrinsic size 是 1024×1024,
        // NSStatusItem button 不会自动缩,直接铺满菜单栏(之前看到的"icon 异常大"bug)
        let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage ?? NSImage()
        icon.size = NSSize(width: 22, height: 22)  // 标准菜单栏 icon size
        item.button?.image = icon
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(handleButtonClick(_:))
        statusItem = item

        // 初次同步可见性
        applyVisibility(container.settingsManager.state.general.showMenuBarIcon)

        // 观察 settings — 之前是 500ms 轮询,App 全程都跑,空转浪费 CPU。
        // 改成 withObservationTracking 订阅,只在 showMenuBarIcon 真的被写入时
        // 才 fire,跟 ThemeController 同一套模式。
        visibilityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                let current = self.container.settingsManager.state.general.showMenuBarIcon
                self.applyVisibility(current)
                // 单次 onChange,re-arm 等下一次写入
                await self.waitForVisibilityChange()
                if Task.isCancelled { return }
            }
        }
    }

    /// 阻塞直到 showMenuBarIcon 字段被写入一次。
    /// withObservationTracking 的 onChange 只 fire 一次,所以外层 while 循环复用。
    private func waitForVisibilityChange() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = self.container.settingsManager.state.general.showMenuBarIcon
            } onChange: {
                continuation.resume()
            }
        }
    }

    private func applyVisibility(_ visible: Bool) {
        guard let item = statusItem else { return }
        if item.isVisible != visible {
            item.isVisible = visible
            if !visible {
                popover?.performClose(nil)
                removeOutsideClickMonitor()
            }
        }
    }

    @objc private func handleButtonClick(_ sender: NSStatusBarButton) {
        guard let button = statusItem?.button else { return }
        if let existing = popover, existing.isShown {
            existing.performClose(nil)
            removeOutsideClickMonitor()
            return
        }
        let p = NSPopover()
        // .applicationDefined:我们自己处理 dismiss。.transient 在 NSPopover +
        // NSHostingController 组合下偶尔不响应外部点击(尤其点主窗口),
        // 表现就是菜单"不隐藏",连带 Quit 也没反应(popover 残留把 willTerminate
        // 拖住)。改成手动监听 leftMouseDown,在 popover 窗口外就关掉。
        p.behavior = .applicationDefined
        p.contentSize = NSSize(width: 320, height: 1)
        p.contentViewController = NSHostingController(
            rootView: MenuBarView().environment(container)
        )
        self.popover = p
        installOutsideClickMonitor()
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// 监听 popover 打开期间的鼠标点击 — 如果点在 popover 窗口外,
    /// 就关闭 popover。覆盖 .transient 在 SwiftUI HostingController 上下文里
    /// 失效的情况(点主窗口 / 点其他应用窗口 / 点桌面都能正确关掉)。
    ///
    /// 关键判定:**event 的目标 NSWindow 是不是 popover 自己的 window**。
    /// 之前用 `popoverWindow.frame.contains(clickInScreen)` 做坐标比较 —
    /// 在 SwiftUI 托管视图 + NSPopover 组合下,坐标系可能因为 window origin /
    /// flipped y 轴等细节偏差,把 popover 内的按钮点击误判成"在外",
    /// 结果 performClose 抢在 button action 之前触发,整行点不动。
    /// 用 window 身份比较是唯一可靠的方式。
    private func installOutsideClickMonitor() {
        // 已存在就先拆,避免重复挂
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self = self,
                  let popover = self.popover,
                  popover.isShown,
                  let popoverWindow = popover.contentViewController?.view.window
            else {
                return event
            }
            // event.window === popoverWindow → 点在 popover 内,放过
            // event.window 是其他 window(主窗口 / 浮动窗口)→ 点在外面,关
            // event.window 是 nil(点桌面 / 其他 app)→ 也算在外面,关
            if event.window !== popoverWindow {
                popover.performClose(nil)
                self.removeOutsideClickMonitor()
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }
}
// MARK: - AppWindowFocus
// 用 AppKit 直接操作 Window — 用于从 NSPopover / 其它非 SwiftUI Window 上下文
// 触发主窗口置顶。\.openWindow env value 在 NSPopover hosted view 里不可用。
@MainActor
enum AppWindowFocus {
    /// 找到主 Window 并 makeKeyAndOrderFront + activate App。
    /// 多重 fallback 策略:
    /// 1. 找 SwiftUI Window id="main" — 通过 title "Janus SSH" 匹配
    /// 2. 找任何带 contentViewController 的窗口
    /// 3. 兜底:NSApp.keyWindow / mainWindow
    static func focusMain() {
        // 强制 App 激活
        NSApp.activate(ignoringOtherApps: true)

        // 候选 1:精确匹配 SwiftUI 主 Window 的 title
        let candidates = NSApp.windows
        let main = candidates.first(where: { $0.title == "Janus SSH" })
            ?? candidates.first(where: { $0.contentViewController != nil && $0.canBecomeMain })
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? candidates.first

        guard let target = main else { return }
        // 解除 miniaturized 状态
        if target.isMiniaturized {
            target.deminiaturize(nil)
        }
        target.makeKeyAndOrderFront(nil)
    }
}

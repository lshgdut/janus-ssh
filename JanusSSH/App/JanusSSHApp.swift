import SwiftUI
import JanusSSHTunnelEngine

@main
struct JanusSSHApp: App {
    @State private var container: AppContainer

    init() {
        let container = AppContainer.bootstrap()
        _container = State(initialValue: container)
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
                    container.menuBarController.start()
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
    /// Popover 刚开 ~300ms 的"burst 窗口":打开过程中 AppKit 会陆续派发多个
    /// mouse/mouseDown events(开 click 的尾巴 + view appearance + swiftui 内部
    /// gesture resolve),这些 event.window 通常是 NSStatusBarWindow 而非 popover,
    /// 走 outside branch 会立刻 performClose。用 **时间窗口** 吞掉整个 burst,
    /// 比 swallow 一条更稳 — 即便 burst 是 N 条 events。
    private var swallowOutsideClickUntil: Date?

    init(container: AppContainer) {
        self.container = container
    }

    /// App 退出路径 — 显式拆 outside-click monitor + 关 popover 再 terminate。
    /// 之前依赖 outside-click monitor 在左键 outside popover 时 dismiss,但
    /// .applicationDefined + NSHostingController 组合下偶发 popover 残留,
    /// 会把 willTerminate 拖住,结果 app 不退出。所以 Quit 路径必须自己负责
    /// dismiss,不能靠 monitor 副作用。
    func quit() {
        removeOutsideClickMonitor()
        if let popover = popover {
            popover.performClose(nil)
        }
        self.popover = nil
        NSApp.terminate(nil)
    }

    /// 关 popover 但不 terminate App — 给 Settings / Refresh SSH Config 这种动作
    /// 用 — 触发后让 popover 收掉,把焦点让给刚打开的新窗口。手动 dismiss 而不是
    /// 靠 outsideClickMonitor 是因为这些 action 是 popover 内按钮触发,monitor
    /// 不会看到它们。
    func dismissPopover() {
        removeOutsideClickMonitor()
        if let popover = popover {
            popover.performClose(nil)
            self.popover = nil
        }
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
        // 幂等 — SwiftUI Window 的 .onAppear 会随窗口 hide/show 多次 fire。
        // 之前没这层 guard,每次 .onAppear 都 NSStatusBar.system.statusItem(...)
        // 新建一个 item,但旧 item 仍在系统 menu bar 里 — 菜单栏上 N 个
        // Janus 图标,点哪个都开同一个 popover。同时 visibilityTask 也是直接
        // 重新赋值,旧 Task 没人 cancel,后台 N 个观察循环在跑。
        //
        // start() 设计成"App 启动时调一次",重复调用一律 no-op,需要重置走
        // shutdown() 再 start()。
        guard statusItem == nil else { return }

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
        debugLog("menu-bar: handleButtonClick fired, button screen=\(statusItem?.button?.window?.screen?.localizedName ?? "nil")")
        guard let button = statusItem?.button else { return }
        if let existing = popover, existing.isShown {
            debugLog("menu-bar: closing existing popover")
            existing.performClose(nil)
            removeOutsideClickMonitor()
            return
        }
        debugLog("menu-bar: creating AutoKeyPopover, super.show below")
        let p = AutoKeyPopover()
        // .applicationDefined:我们自己处理 dismiss。.transient 在 NSPopover +
        // NSHostingController 组合下偶尔不响应外部点击(尤其点主窗口),
        // 表现就是菜单"不隐藏",连带 Quit 也没反应(popover 残留把 willTerminate
        // 拖住)。改成手动监听 leftMouseDown,在 popover 窗口外就关掉。
        p.behavior = .applicationDefined

        // ⚠️ 内容尺寸必须显式设 — 不能依赖 NSPopover 自动算 hosting view 的
        // intrinsicContentSize。NSHostingController + .frame(width:) 的组合下,
        // 高度是 dynamic(intrinsic),但 NSPopover 在 show() 时取的尺寸经常是
        // SwiftUI layout 之前的 stale 值,hosting view 装不下整个 MenuBarView,
        // 底部 hover 高亮和 hit-test 都被截掉。
        //
        // 修法:装好 contentViewController,主动 layoutSubtreeIfNeeded() 让
        // SwiftUI 把 VStack 真正折叠一遍,fit 出准确高度,再设 contentSize。
        // 这样 NSPopover 拿到的尺寸跟实际内容对齐,hit-test 全覆盖。
        //
        // 同时用 KeyableHostingController(见下)替代直接 NSHostingController —
        // `.applicationDefined` NSPopover 的窗口默认 `becomesKeyOnlyOnUserAction
        // = true`,第一次 mouseDown 会被 AppKit 抢去做 key-window promotion,
        // 按钮 action 不触发 — 表现就是"点两下才生效"。Subclass 在 viewDidAppear
        // 立即 window?.makeKey(),让 popover 一出现就拿 key,后续 button 第一次
        // 点击直接走 target/action,不再被 promotion 抢先消耗。
        let host = KeyableHostingController(
            rootView: MenuBarView().environment(container)
        )
        host.view.layoutSubtreeIfNeeded()
        let fittedHeight = host.view.fittingSize.height
        p.contentSize = NSSize(
            width: 320,  // 必须跟 MenuBarView.popoverWidth 一致
            height: max(fittedHeight, 1)
        )
        p.contentViewController = host

        self.popover = p
        installOutsideClickMonitor()
        debugLog("menu-bar: p.show(...) called, statusItem screen=\(button.window?.screen?.localizedName ?? "nil")")
        // 时间窗口 swallow:开 popover 后 ~300ms 内 monitor 一律 pass-through,
        // 避开"开 click 尾巴 + view 渲染 + SwiftUI gesture resolve"陆续到达
        // 的 burst 都被误判成 outside click 立刻关掉 popover。详情见 monitor
        // 注释。
        swallowOutsideClickUntil = Date().addingTimeInterval(0.3)
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
            // burst 窗口内一律 pass-through — 见 swallowOutsideClickUntil 设置处注释。
            if let until = self.swallowOutsideClickUntil, Date() < until {
                debugLog("outsideClickMonitor: burst window pass-through (event.window=\(String(describing: event.window)))")
                return event
            }
            // event.window === popoverWindow → 点在 popover 内,放过
            // event.window 是其他 window(主窗口 / 浮动窗口)→ 点在外面,关
            // event.window 是 nil(点桌面 / 其他 app)→ 也算在外面,关
            if event.window !== popoverWindow {
                debugLog("outsideClickMonitor: outside click, event.window=\(String(describing: event.window)), popoverWindow=\(popoverWindow), closing")
                popover.performClose(nil)
                self.removeOutsideClickMonitor()
            } else {
                debugLog("outsideClickMonitor: inside popover click, event.window matches popoverWindow, pass-through")
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

/// NSPopover 内的 SwiftUI hosting controller — viewDidAppear 强制 makeKey。
///
/// `.applicationDefined` NSPopover 用的 NSPanel 默认不会主动抢占 key,popover
/// 上场时 isKeyWindow == false。第一次 mouseDown 落在 popover 内 button 上时,
/// AppKit 把那次点击用做 key-window promotion,按钮 action 不触发 — 用户看到的
/// 就是"点 Settings / Quit 要两下才生效"。NSHostingController 默认不覆盖
/// viewDidAppear,我们在子类里 view 一出现在 AppKit 派发任何鼠标事件之前调
/// `window?.makeKey()`,把 popover 锁到 key 状态,后续 button 第一次点击直接走
/// normal target/action,不再被 promotion 抢先消耗。
/// Subclass NSHostingController — viewDidAppear 强制 makeKey(belt-and-suspenders)。
///
/// SwiftUI hosting controller 在某些 macOS 版本下 viewDidAppear 触发时点已经在
/// NSHostingController 上,primary fix 已经走 AutoKeyPopover.show()(见下),
/// 这里再追加一道兜底,确保 popover window 在任何路径下都能进 key state。
private final class KeyableHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidAppear() {
        super.viewDidAppear()
        let win = view.window
        debugLog("KeyableHostingController.viewDidAppear: window=\(win != nil), isKey=\(win?.isKeyWindow ?? false), screen=\(win?.screen?.localizedName ?? "nil")")
        win?.makeKey()
    }
}

/// NSPopover subclass — show() 后立刻调度 makeKey 进 key state,绕过 `.applicationDefined`
/// 默认不会抢占 key 的问题。
///
/// 为什么 viewDidAppear 兜底还不够:`.applicationDefined` NSPopover 用的 NSPanel 默认
/// `becomesKeyOnlyOnUserAction = true`(Swift 没暴露这个属性),popover 上场时
/// `isKeyWindow == false`。第一次 mouseDown 落在 popover 内 button 上时,AppKit 把那次
/// 点击用做 key-window promotion,按钮 action 不触发 — 表现就是 "Settings/Quit 要点
/// 两下才生效",而在某些 macOS 版本下 NSHostingController.viewDidAppear 时机晚于用户
/// 第一次点击能看到的事件,完全错过拦截窗口。
///
/// 修法:AutoKeyPopover 覆盖两条 show() 入口,super.show() 后 `DispatchQueue.main.async`
/// 强制把 contentViewController 的 window makeKey — 这时 popover 的 NSPanel 已经
/// 完整 wiring,view.window 不为 nil,makeKey 立刻升 key,后续 button 第一次点击直接
/// 走 normal target/action,不再被 promotion 抢先消耗。
private final class AutoKeyPopover: NSPopover {
    override func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        super.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
        makeKeyOnNextRunloop()
    }

    /// 把 makeKey 调度到下一个 main runloop tick — 这时 popover 内部 NSPanel 已经
    /// wire 完整,contentViewController?.view.window 不再是 nil。
    private func makeKeyOnNextRunloop() {
        debugLog("AutoKeyPopover: scheduling makeKey on next runloop")
        let popoverRef = self
        DispatchQueue.main.async {
            let win = popoverRef.contentViewController?.view.window
            debugLog("AutoKeyPopover: runloop fired, window=\(win != nil), isKey=\(win?.isKeyWindow ?? false), screen=\(win?.screen?.localizedName ?? "nil")")
            win?.makeKey()
            debugLog("AutoKeyPopover: after makeKey, isKey=\(win?.isKeyWindow ?? false)")
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

// MARK: - 调试日志(临时)

/// 调试期写到 `~/Library/Logs/JanusSSH/menu-bar-debug.log`,每行带时间戳。
/// 同时 print 出来让 Console.app / `log stream` 能看到。问题修完会删。
func debugLog(_ msg: @autoclosure () -> String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg())"
    let formatted = "[JanusSSH-debug] \(line)"
    print(formatted)
    let dir = NSString("~/Library/Logs/JanusSSH").expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = (dir as NSString).appendingPathComponent("menu-bar-debug.log")
    let payload = (line + "\n").data(using: .utf8) ?? Data()
    if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
        h.seekToEndOfFile()
        h.write(payload)
        try? h.close()
    } else {
        try? payload.write(to: URL(fileURLWithPath: path))
    }
}


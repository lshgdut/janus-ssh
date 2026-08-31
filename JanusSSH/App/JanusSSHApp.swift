import SwiftUI
import AppKit
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

        // Menu Bar — 走 SwiftUI MenuBarExtra(.window 风格),不要 NSPopover。
        //
        // 为什么不用 NSPopover:
        //   1) NSPopover 自带三角箭头(speech-bubble tail),跟 Slack / Things /
        //      Notion Calendar 这些现代 menu bar app 的"干净无三角"观感不一致。
        //   2) NSPopover + .applicationDefined + NSHostingController 组合有
        //      一堆 corner case 要 hack — outside-click monitor、burst window
        //      swallow、KeyableHostingController 强制 makeKey、AutoKeyPopover
        //      异步抢占 key 状态...全是补 NSPopover 的洞。MenuBarExtra 是
        //      SwiftUI 原生,系统自动管 outside-click / Escape / focus change
        //      dismissal,代码大幅简化。
        //
        // isInserted binding 直读 settingsManager.state.general.showMenuBarIcon —
        // SwiftUI scene 通过 binding 的 getter 追踪 @Observable 依赖,
        // Settings 改 toggle 后 MenuBarExtra 自动从系统菜单栏 add/remove icon。
        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarView()
                .environment(container)
                // MenuBarExtra(.window) 创建的 NSPanel 跟 NSPopover +
                // .applicationDefined 同样有 `becomesKeyOnlyOnUserAction` 行为:
                // popover 上场时 isKeyWindow == false,首次 mouseDown 会被
                // AppKit 抢去做 key-window promotion,SwiftUI 的 Button /
                // onTapGesture 全都不 fire — 表现就是"点 menu item 没反应"
                // (其实是首 click 被吞了,第二次才正常)。WindowAccessor 在
                // SwiftUI hosting view 进 view tree 时拿到 .window 引用,
                // 下一个 main runloop 强制 makeKey,把 panel 提前锁到 key
                // 状态,后续点击直接走 normal target/action 路径。
                .background(MenuBarWindowAccessor())
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)

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

    /// 菜单栏图标可见性 binding — 直读/写 settingsManager。
    /// SwiftUI scene 系统通过 binding 的 getter 追踪 `@Observable` 依赖,
    /// `settingsManager.state` 任意字段变更都触发 scene re-evaluation。
    /// setter 走 `settingsManager.update { ... }`,跟 SettingsView 的 toggle
    /// 走同一条持久化路径,不会跟磁盘文件脱节。
    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { container.settingsManager.state.general.showMenuBarIcon },
            set: { newValue in
                Task { await container.settingsManager.update { $0.general.showMenuBarIcon = newValue } }
            }
        )
    }

    /// 菜单栏图标 — 复用 AppIcon asset catalog,与 Dock 图标保持 100% 一致。
    /// NSImage.size 设为 22pt 给 MenuBarExtra 一个渲染 hint,SwiftUI 这边再
    /// 显式 .frame(22x22) 兜底 — 不同 macOS 版本 MenuBarExtra 对内嵌 NSImage
    /// 的 intrinsic size 处理略有差异,两边都给尺寸最稳。
    @ViewBuilder
    private var menuBarIcon: some View {
        Image(nsImage: makeMenuBarIcon())
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 22, height: 22)
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
    /// NSImage(named: "AppIcon") 由 asset catalog 提供,自带 macOS squircle 蒙版和
    /// 高分辨率渲染,@2x 实际 44×44 像素。size 设为 22pt 给 MenuBarExtra 一个 hint。
    fileprivate func makeMenuBarIcon() -> NSImage {
        let image = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage ?? NSImage()
        image.size = NSSize(width: 22, height: 22)
        return image
    }
}

// MARK: - MenuBarWindowAccessor
// 强制 MenuBarExtra(.window) 的 NSPanel 提前 makeKey,绕过
// `becomesKeyOnlyOnUserAction = true` 那个"首次 mouseDown 被 AppKit 抢做
// key-window promotion、SwiftUI Button 不 fire"的坑 — 表现就是用户要点
// 两次才生效(第一次被吞,第二次才走到 button action)。
//
// 第一版用 `DispatchQueue.main.async { view.window?.makeKey() }` 失败,
// 因为 makeNSView 时 SwiftUI hosting tree 还没装载,view.window 是 nil,
// async 走到时 panel 还没真正 addSubview 这棵 view。继续 viewDidMoveToWindow
// 的 hook — AppKit 保证它在 view 真的进了 panel 时 fire,这时 view.window
// 已经指向 panel,makeKey 稳定生效。
//
// 仍然调度到下一 runloop tick 再 makeKey(不是直接同步),是为了避开
// viewDidMoveToWindow 时 NSPanel 还在 install-layout 阶段、同步 makeKey
// 会撞 layout pass 触发 AppKit 警告。
private final class MenuBarKeyableView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }
        let target = window
        DispatchQueue.main.async { [weak target] in
            target?.makeKey()
        }
    }
}

struct MenuBarWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MenuBarKeyableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 每次 SwiftUI re-evaluate view 时,view 可能已经在 tree 里,
        // viewDidMoveToWindow 已经 fire 过一次。但 MenuBarExtra(.window)
        // 重新 show panel 时 hosting view 可能重新挂到新 window,
        // viewDidMoveToWindow 会再 fire。这里不需要主动 re-makeKey —
        // 同一 window 重复 makeKey 是 no-op。
    }
}

// MARK: - AppWindowFocus
// 用 AppKit 直接操作 Window — 用于从 MenuBarExtra 触发主窗口置顶。
// \.openWindow env value 在 MenuBarExtra hosted view 里不可用。
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
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
        WindowGroup("Janus SSH", id: "main") {
            RootView()
                .environment(container)
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

        // 独立 Profile Editor 窗口 — 避开 .sheet 的固定尺寸截断
        // 监听 container.editingProfile,非 nil 时显示
        WindowGroup("Edit Profile", id: "profile-editor") {
            ProfileEditorWindow()
                .environment(container)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 720)

        MenuBarExtra {
            MenuBarView()
                .environment(container)
        } label: {
            // Template NSImage — macOS 自动反色适配 light/dark menu bar
            Image(nsImage: makeMenuBarIcon())
        }
        // .window 模式:用 SwiftUI 自定义 popover(蓝 S badge、dark material、
        // hover 显示 Stop/Retry、自定义快捷键样式等),完全按设计稿还原。
        // 之前用 .menu 模式是为了规避 NSXPCDecoder 警告,但代价是所有
        // SwiftUI 自定义样式被原生 NSMenu 吞掉,设计还原度为零。
        // .window 的 XPC 警告是警告而非 error,功能上正常,这里以视觉为优先。
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(container)
                .frame(minWidth: 720, minHeight: 560)
        }
    }
}

extension Notification.Name {
    static let newProfileRequested = Notification.Name("janus.newProfileRequested")
}

extension JanusSSHApp {
    /// 构造 menu bar 图标 — 复用 AppIcon 的 Janus 双弧设计
    /// 用 Core Graphics 直接画到 NSImage,单色 template
    /// macOS 看到 isTemplate=true 会自动反色(light → 黑,dark → 白)
    fileprivate func makeMenuBarIcon() -> NSImage {
        let size = CGFloat(32)  // @2x 实际渲染尺寸
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high

        // 颜色:全黑(纯 alpha)— macOS 反色后会变成白
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let lineWidth = size * 0.14
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        // 左弧 (开口向右,代表 Janus 一张脸)
        let leftCx = size * 0.5 - size * 0.13
        let arcR = size * 0.21
        ctx.addArc(
            center: CGPoint(x: leftCx, y: size * 0.5),
            radius: arcR,
            startAngle: 30, endAngle: 330,
            clockwise: false
        )
        ctx.strokePath()

        // 右弧 (开口向左,代表 Janus 另一张脸)
        let rightCx = size * 0.5 + size * 0.13
        ctx.addArc(
            center: CGPoint(x: rightCx, y: size * 0.5),
            radius: arcR,
            startAngle: 150, endAngle: 90,
            clockwise: false
        )
        ctx.strokePath()

        // 中心点 — 隧道焦点
        let dotR = size * 0.08
        let dotRect = CGRect(
            x: size * 0.5 - dotR,
            y: size * 0.5 - dotR,
            width: dotR * 2, height: dotR * 2
        )
        ctx.fillEllipse(in: dotRect)

        // 关键:标记为 template — macOS 自动反色
        image.isTemplate = true
        return image
    }
}
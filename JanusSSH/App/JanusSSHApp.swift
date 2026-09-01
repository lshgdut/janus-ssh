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
        //
        // MenuBarView 内部用 SwiftUI @FocusState + .focusable() 在 onAppear
        // 主动 grab focus,自然把 MenuBarExtra 的 NSPanel 升 key — 不需要
        // NSViewRepresentable 跨进 AppKit 拿 .window 强制 makeKey。
        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarView()
                .environment(container)
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

    /// 菜单栏图标 — 走 SF Symbol template 模式,符合 macOS 规范。
    ///
    /// 为什么不用 AppIcon(asset catalog 那个彩色 squircle):
    ///   - macOS menu bar icon 规范要求 template image(单色 + alpha 通道),
    ///     系统按 menu bar 当前文字色自动 tint(浅 menu bar 黑色,深 menu
    ///     bar 白色)。
    ///   - AppIcon 是彩色渐变,塞进 menu bar 不 tint,跟周围所有图标
    ///     视觉冲突。Slack / 1Password / Things / Notion Calendar 等所有
    ///     主流 menu bar app 都是 SF Symbol 或自制 monochrome PNG。
    ///
    /// `arrow.triangle.swap` — SF Symbol 4(macOS 14+)两个三角箭头互换,
    /// 跟 Janus 双脸/双向的语义贴。如果看起来不像 logo,备选:
    ///   - `arrow.triangle.2.circlepath`(两个箭头沿圆路径)
    ///   - `arrow.left.and.right`(简单双向箭头)
    ///   - `arrow.left.and.right.circle`(圆形里的双向箭头)
    /// 换一行 systemName 即可,monochrome template 渲染保持不变。
    @ViewBuilder
    private var menuBarIcon: some View {
        // 标准方案 — 从 AppIcon 提取白色 glyph → 转成黑色 + 透明 template
        // NSImage。Canvas / Shape / SF Symbol 都不跟 app logo 视觉一致,
        // 只有从现有 AppIcon 直接抠 glyph 才是 1:1 还原。
        //
        // **不**加 .frame(width: 22, height: 22) — NSImage.size 已经是
        // 22x22(见 MenuBarIconFactory),MenuBarExtra 按这个尺寸 layout。
        // 再加 frame 在 MenuBarExtra label 上下文里有时会被覆盖。
        Image(nsImage: MenuBarIconFactory.templateIcon)
            .interpolation(.high)
            .accessibilityLabel(Text("Janus SSH"))
    }
}

// MARK: - MenuBarIconFactory
// 从现有 AppIcon 提取白色 glyph(两个 C 弧 + 中心点) → 黑色 + 透明
// 背景的 template NSImage。这是 macOS menu bar icon 的标准做法:
//
//   1. macOS menu bar icon **必须是 template image**(单色 + 透明),
//      system 按 menu bar 当前文字色自动 tint。
//   2. SwiftUI MenuBarExtra 的 label 里用 `Image(nsImage:)` 渲染 NSImage
//      是最稳的路径 — Canvas / Shape / SF Symbol 在 MenuBarExtra 上下文
//      都有渲染异常案例(详见之前 JanusMenuBarIcon Shape 方案的 bug)。
//   3. AppIcon 是彩色 squircle + 白 glyph,我们只需要 glyph 部分 —
//      蓝色背景的像素全部转成透明,白色像素转成黑色,就得到一个
//      跟 brand 1:1 的 monochrome template。
//
// 实现要点:
//   - 从 NSImage(named: "AppIcon") 拿 cgImage,用 CGContext 渲染到 64x64
//     bitmap(AppIcon 原始是 1024x1024,直接缩到 64x64 glyph 边缘会糊,
//     64px @ Retina 渲染够锐)。
//   - 遍历像素:luminance > 0.78 视为 glyph(白色部分),转成黑色 opaque;
//     否则转成透明。
//   - `isTemplate = true` 告诉 system 这张图是 template,menu bar 自动
//     按文字色 tint。
//   - 缓存到 `templateIcon` static let — 首次访问时算一次,后续直接用。
@MainActor
enum MenuBarIconFactory {
    /// 缓存的 template NSImage — App 启动后首次访问时生成,之后不再重算
    static let templateIcon: NSImage = makeTemplateIcon()

    private static func makeTemplateIcon() -> NSImage {
        let bitmapSize = 88     // 内部 bitmap 物理分辨率(给 retina 锐利)
        let logicalSize = 22.0  // NSImage.size — SwiftUI/MenuBarExtra 按这个 layout

        // 1. 加载 AppIcon(彩色 squircle + 白 glyph)
        guard let original = NSImage(named: "AppIcon"),
              let cgImage = original.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSImage()
        }

        // 2. **裁剪到 glyph bounding box** — 关键。AppIcon 设计成 squircle
        // 撑满 1024x1024 canvas,glyph(两个 C 弧 + 中心点)在 squircle
        // 里只占 ~50% 区域,squircle 给 glyph 留了大量空白。如果直接
        // 把整张 AppIcon 渲染到 slot,glyph 怎么都只能占 slot 的 50%。
        //
        // 先 detect glyph 最小包围矩形 → cropping 裁掉 squircle 给 glyph
        // 留的空白 → 渲染到 slot 时 glyph 自然占满 ~95%。
        let effectiveImage: CGImage
        if let cropped = cropToGlyph(in: cgImage) {
            effectiveImage = cropped
        } else {
            effectiveImage = cgImage  // fallback:detect 失败
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: bitmapSize,
            height: bitmapSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return NSImage()
        }

        // 4% padding — 裁过的 glyph 几乎贴满 slot,留一丝防 AA 截断
        let padding: CGFloat = 0.04
        let drawSize = CGFloat(bitmapSize) * (1 - 2 * padding)
        let drawOffset = CGFloat(bitmapSize) * padding

        context.interpolationQuality = .high
        context.draw(effectiveImage, in: CGRect(x: drawOffset, y: drawOffset, width: drawSize, height: drawSize))

        // 3. **Color-channel equality 检测** — 比纯 luminance 准。
        //
        // 之前用 luminance 阈值会有问题:
        //   - 蓝色 squircle 背景 luminance ≈ 0.49
        //   - anti-aliased 白边缘像素 luminance ≈ 0.55-0.85
        //   - 两类 luminance 重叠,纯阈值会误把蓝色背景的"亮区"
        //     当成 glyph 边缘 → menu bar 上看到"鬼影 squircle"。
        //
        // 改用 (R≈G≈B) 判定:glyph 像素 R G B 三个通道几乎相等,
        // 蓝色背景 B 通道显著大于 R/G。两者在"channel equality"
        // 这个特征上分得很干净。
        guard let dataPtr = context.data else { return NSImage() }
        let pixelData = dataPtr.bindMemory(to: UInt8.self, capacity: bitmapSize * bitmapSize * 4)
        let totalPixels = bitmapSize * bitmapSize

        let blueDominanceCutoff: Double = 0.10  // B 比 R/G 高出多少算"是蓝色"
        let alphaLo: Double = 0.50              // 平均亮度低于此值 → 透明
        let alphaHi: Double = 0.95              // 高于此值 → opaque

        for i in 0..<totalPixels {
            let offset = i * 4
            let r = Double(pixelData[offset]) / 255.0
            let g = Double(pixelData[offset + 1]) / 255.0
            let b = Double(pixelData[offset + 2]) / 255.0

            // 蓝色 dominance — B 比 R/G 高出的归一化值
            let blueDominance = b - max(r, g)

            let alpha: Double
            if blueDominance > blueDominanceCutoff {
                // 蓝色 squircle 背景(包括高光渐变区) → 完全透明
                alpha = 0
            } else {
                // glyph 或 anti-aliased 边缘像素 → 按 R G B 平均亮度
                let avg = (r + g + b) / 3.0
                if avg <= alphaLo {
                    alpha = 0
                } else if avg >= alphaHi {
                    alpha = 1
                } else {
                    // 平滑过渡 — 保留 anti-aliased 边缘
                    alpha = (avg - alphaLo) / (alphaHi - alphaLo)
                }
            }

            pixelData[offset]     = 0   // R = black
            pixelData[offset + 1] = 0   // G = black
            pixelData[offset + 2] = 0   // B = black
            pixelData[offset + 3] = UInt8((alpha * 255).rounded())
        }

        // 4. **关键**:NSImage.size 设成 22x22,而不是 bitmap 88x88。
        //
        // SwiftUI `Image(nsImage:)` 的 intrinsic content size 直接用
        // NSImage.size。如果留 88x88,MenuBarExtra label 按 88pt 渲染
        // → menu bar 上的 icon 顶天立地比标准 icon 大好几倍。
        // NSImage.size = 22x22 + 内部 CGImage 88x88 = logical 22pt +
        // retina 4x 采样,这是 Apple 推荐的标准做法。
        guard let outputCGImage = context.makeImage() else {
            return NSImage()
        }
        let templateImage = NSImage(cgImage: outputCGImage, size: NSSize(width: logicalSize, height: logicalSize))
        templateImage.isTemplate = true
        return templateImage
    }

    /// 扫描 AppIcon CGImage 的 pixel buffer,找出白色 glyph 的最小包围
    /// 矩形,裁掉 squircle 留白。返回裁过的 CGImage(包含 32px margin)。
    ///
    /// 实现要点:
    ///   - **半分辨率采样**(stride=2):1M → 256K,~4x 加速,glyph 检测
    ///     精度足够(margin 32px 容错大)。
    ///   - **Y 坐标**:CGImage 默认 bottom-up(PNG 数据 layout top-down)。
    ///     我们从 top→bottom 扫描 memory,scan 结果转 CGImage crop rect
    ///     时 `cgY = height - 1 - memY`。
    ///   - 像素判据 `avg > 0.65 && blueDom < 0.10` = 白色 glyph(R≈G≈B)。
    ///   - margin 32 px 给 anti-aliased 边缘留余量。
    private static func cropToGlyph(in cgImage: CGImage) -> CGImage? {
        let height = cgImage.height
        let width = cgImage.width
        let bytesPerRow = cgImage.bytesPerRow
        let bpp = cgImage.bitsPerPixel / 8

        guard let dataProvider = cgImage.dataProvider,
              let cfData = dataProvider.data,
              let ptr = CFDataGetBytePtr(cfData) else {
            return nil
        }

        let step = 2
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        var found = false

        // memory row 0 = top of image(PNG 是 top-down 存储)
        for memY in Swift.stride(from: 0, to: height, by: step) {
            for memX in Swift.stride(from: 0, to: width, by: step) {
                let offset = memY * bytesPerRow + memX * bpp
                let r = Double(ptr[offset]) / 255.0
                let g = Double(ptr[offset + 1]) / 255.0
                let b = Double(ptr[offset + 2]) / 255.0

                let avg = (r + g + b) / 3.0
                let blueDom = b - max(r, g)

                if avg > 0.65 && blueDom < 0.10 {
                    if memX < minX { minX = memX }
                    if memX > maxX { maxX = memX }
                    if memY < minY { minY = memY }
                    if memY > maxY { maxY = memY }
                    found = true
                }
            }
        }

        guard found else { return nil }

        // memory Y → CGImage Y(bottom-up):cgY = height - 1 - memY
        // crop rect.y = glyph bottom 在 CGImage 坐标
        let margin = 32
        let rectX = max(0, minX - margin)
        let rectW = min(width - rectX, (maxX - minX + 1) + margin * 2)
        let rectY_cg = max(0, height - 1 - maxY - margin)
        let rectH = min(height - rectY_cg, (maxY - minY + 1) + margin * 2)

        return cgImage.cropping(to: CGRect(x: rectX, y: rectY_cg, width: rectW, height: rectH))
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
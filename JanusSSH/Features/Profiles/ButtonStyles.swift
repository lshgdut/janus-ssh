import SwiftUI
import AppKit

// MARK: - Design tokens
// 对齐 OpenDesign dashboard.html :root 与 .btn-primary 样式

enum DesignTokens {
    static let accent       = Color(red: 0.243, green: 0.416, blue: 0.882)
    static let accentHover  = Color(red: 0.190, green: 0.340, blue: 0.770) // ≈ accent × black 18%
    static let accentActive = Color(red: 0.155, green: 0.290, blue: 0.685) // ≈ accent × black 30%

    static let surfaceHover = Color(nsColor: .controlBackgroundColor)
    static let surfaceHoverStrong = Color(nsColor: .controlAccentColor).opacity(0.15)
    static let bg           = Color(nsColor: .windowBackgroundColor)
    static let borderSoft   = Color(nsColor: .separatorColor)
    static let fg           = Color(nsColor: .labelColor)

    static let buttonHeight: CGFloat = 32
    static let buttonRadius: CGFloat = 4
    static let buttonHPadding: CGFloat = 16
    static let buttonTransition: Double = 0.15  // 150ms
}

// MARK: - Primary (Start / Retry) — 蓝底白字

struct PrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration)
    }
}

private struct PrimaryBody: View {
    let configuration: PrimitiveButtonStyle.Configuration
    @State private var isHovered = false
    @GestureState private var isPressing = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isPressed = isPressing
        // disabled 状态:用淡化的 accent 色作为 bg,文字也降透明度,
        // 让按钮一眼看上去"不可点"
        let bg: Color = {
            if !isEnabled { DesignTokens.accent.opacity(0.4) }
            else if isPressed { DesignTokens.accentActive }
            else if isHovered { DesignTokens.accentHover }
            else { DesignTokens.accent }
        }()
        let fg: Color = isEnabled ? .white : .white.opacity(0.7)

        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(fg)
            .lineLimit(1)                        // 禁止文字在按钮内换行
            .fixedSize(horizontal: true, vertical: false)  // 按钮保持自然宽度
            .frame(height: DesignTokens.buttonHeight)
            .padding(.horizontal, DesignTokens.buttonHPadding)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.buttonRadius))
            .contentShape(Rectangle())
            // disabled 时不切手指光标、不响应 hover 高亮
            .onHover { hovering in
                guard isEnabled else { return }
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
                    .onEnded { _ in configuration.trigger() }
            )
            .animation(.easeInOut(duration: DesignTokens.buttonTransition),
                       value: isHovered)
            .animation(.easeInOut(duration: DesignTokens.buttonTransition),
                       value: isPressed)
    }
}

// MARK: - Secondary (Stop) — 白底深字 + 边框

struct SecondaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration)
    }
}

private struct SecondaryBody: View {
    let configuration: PrimitiveButtonStyle.Configuration
    @State private var isHovered = false
    @GestureState private var isPressing = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isPressed = isPressing
        // disabled:背景 + 文字都降到低对比度,边框变淡,
        // 视觉上一眼就是"不可点"状态
        let bg: Color = {
            if !isEnabled { DesignTokens.bg.opacity(0.5) }
            else if isPressed { DesignTokens.surfaceHoverStrong.opacity(0.6) }
            else if isHovered { DesignTokens.surfaceHoverStrong }
            else { DesignTokens.bg }
        }()
        let fg: Color = isEnabled ? DesignTokens.fg : DesignTokens.fg.opacity(0.4)
        let border: Color = isEnabled
            ? (isHovered ? Color(nsColor: .separatorColor).opacity(0.8) : DesignTokens.borderSoft)
            : Color(nsColor: .separatorColor).opacity(0.3)

        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(fg)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: DesignTokens.buttonHeight)
            .padding(.horizontal, DesignTokens.buttonHPadding)
            .background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.buttonRadius)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.buttonRadius))
            .contentShape(Rectangle())
            // disabled 时不响应 hover、不切光标
            .onHover { hovering in
                guard isEnabled else { return }
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
                    .onEnded { _ in configuration.trigger() }
            )
            .animation(.easeInOut(duration: DesignTokens.buttonTransition),
                       value: isHovered)
            .animation(.easeInOut(duration: DesignTokens.buttonTransition),
                       value: isPressed)
    }
}

// MARK: - 便捷静态访问 — 让调用方写 .buttonStyle(.appPrimary) / .appSecondary
// 与 SwiftUI 原生 .bordered / .borderedProminent 一致风格,直接走设计系统 tokens。
// 注:PrimitiveButtonStyle 自带 .buttonStyle 重载,所以这里扩展 PrimitiveButtonStyle
// 而不是 ButtonStyle(Swift 在这个 where 子句下推不出 ButtonStyle 路径)。

extension PrimitiveButtonStyle where Self == PrimaryButtonStyle {
    static var appPrimary: PrimaryButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == SecondaryButtonStyle {
    static var appSecondary: SecondaryButtonStyle { .init() }
}

// MARK: - Hover highlight
//
// 统一的"hover 时背景高亮"修饰,集中控制 opacity / padding / 形状。
// 之前 MenuBarProfileRow / MenuBarItem / SidebarRow / StepperItem 四处
// 各自抄一份 `RoundedRectangle(cornerRadius: 6).fill(hovering ? accent.opacity(...) : .clear)`
// — 0.18 / 0.35 漂移,design token 在调用方完全没用上。
//
// 用法:@State hovering + .hoverHighlight(hovering)

struct HoverHighlight: ViewModifier {
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme
    var lightOpacity: Double = 0.18
    var darkOpacity: Double = 0.35
    var padding: CGFloat = 6
    var cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered
                          ? Color.accentColor.opacity(colorScheme == .dark ? darkOpacity : lightOpacity)
                          : .clear)
                    .padding(.horizontal, padding)
            )
    }
}

extension View {
    /// 一行调用 — 装一个跟 MenuBar 现有 hover 视觉一致的背景。
    /// 默认 light 0.18 / dark 0.35 是 MenuBar 现状;SidebarRow 用 0.15 / 0.30
    /// 时显式覆盖。
    func hoverHighlight(
        _ isHovered: Bool,
        lightOpacity: Double = 0.18,
        darkOpacity: Double = 0.35,
        padding: CGFloat = 6,
        cornerRadius: CGFloat = 6
    ) -> some View {
        modifier(HoverHighlight(
            isHovered: isHovered,
            lightOpacity: lightOpacity,
            darkOpacity: darkOpacity,
            padding: padding,
            cornerRadius: cornerRadius
        ))
    }
}

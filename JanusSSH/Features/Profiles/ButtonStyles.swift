import SwiftUI

// MARK: - Design tokens
// 对齐 OpenDesign dashboard.html :root 与 .btn-primary 样式

enum DesignTokens {
    static let accent       = Color(red: 0.243, green: 0.416, blue: 0.882)
    static let accentHover  = Color(red: 0.219, green: 0.374, blue: 0.793) // ≈ accent × black 8%
    static let accentActive = Color(red: 0.195, green: 0.333, blue: 0.705) // ≈ accent × black 14%

    static let surfaceHover = Color(nsColor: .controlBackgroundColor)
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

    var body: some View {
        let isPressed = isPressing
        let bg: Color = {
            if isPressed { DesignTokens.accentActive }
            else if isHovered { DesignTokens.accentHover }
            else { DesignTokens.accent }
        }()

        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: DesignTokens.buttonHeight)
            .padding(.horizontal, DesignTokens.buttonHPadding)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.buttonRadius))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
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

    var body: some View {
        let isPressed = isPressing
        let bg: Color = {
            if isPressed { DesignTokens.surfaceHover.opacity(0.85) }
            else if isHovered { DesignTokens.surfaceHover }
            else { DesignTokens.bg }
        }()

        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DesignTokens.fg)
            .frame(height: DesignTokens.buttonHeight)
            .padding(.horizontal, DesignTokens.buttonHPadding)
            .background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.buttonRadius)
                    .strokeBorder(DesignTokens.borderSoft, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.buttonRadius))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
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

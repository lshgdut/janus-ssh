import SwiftUI
import JanusSSHTunnelEngine

/// Compact status indicator for tunnel lifecycle states.
///
/// Two visual modes:
/// - `.full`    — colored dot + label inside a tinted pill (default)
/// - `.compact` — colored dot only, suitable for tight rows (e.g. menu bar)
///                `.running` state animates a soft green breathing halo
///                so users can see at-a-glance which tunnels are live.
///
/// Colors come from `AppStatusColor`; labels are localized in the future
/// but currently hardcoded English (see plan item: extract strings).
struct StatusBadge: View {
    enum Style { case full, compact }

    let state: TunnelState
    var style: Style = .full

    var body: some View {
        switch style {
        case .compact:
            CompactStatusDot(state: state)
        case .full:
            HStack(spacing: 6) {
                CompactStatusDot(state: state, size: 6)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(backgroundFill, in: Capsule())
            .foregroundStyle(AppStatusColor.color(for: state))
        }
    }

    private var label: String {
        switch state {
        case .running: return "Running"
        case .starting: return "Starting"
        case .reconnecting: return "Reconnecting"
        case .error: return "Error"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        }
    }

    private var backgroundFill: Color {
        AppStatusColor.color(for: state).opacity(0.12)
    }
}

/// 8x8 colored dot used in both styles. `.running` adds a breathing halo
/// (larger faded circle behind, synced to the same pulse) so the dot
/// appears to "breathe" — visual cue for "alive, no need to check".
///
/// Layout footprint is fixed at 8x8 — the halo extends visually beyond
/// that frame via `.scaleEffect`, but the parent HStack only sees 8x8
/// so surrounding rows do not shift.
private struct CompactStatusDot: View {
    let state: TunnelState
    var size: CGFloat = 8

    // 初始就是 true — 不要 .onAppear 里再改。popover 打开时 N 个 badge 同时
    // .onAppear,每个改 pulse 都会触发 SwiftUI re-render,撞上 AppKit 的
    // window install-layout pass,产生 layoutSubtreeIfNeeded recursion warning。
    // 初始 true 让 animation 直接从当前值出发,避免 onAppear 改 state。
    @State private var pulse = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = AppStatusColor.color(for: state)
        let isRunning = state == .running && !reduceMotion
        ZStack {
            // Halo: only for .running. Stays visible across the whole cycle
            // (opacity dips to ~0.15 at peak, never reaches 0) so the green
            // saturation is preserved on dark backgrounds. Scale grows
            // from ~1.4x → ~3.6x so the breathing range is clearly readable.
            if isRunning {
                Circle()
                    .fill(color.opacity(pulse ? 0.12 : 0.55))
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 3.6 : 1.4)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: pulse
                    )
            }
            // Solid dot — also gently breathes when running
            Circle()
                .fill(color.opacity(isRunning ? (pulse ? 0.6 : 1.0) : 1.0))
                .frame(width: size, height: size)
                .animation(
                    isRunning
                        ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
        }
        .frame(width: size, height: size)
    }
}

/// Inline preview used by Xcode's canvas — not part of the runtime.
#Preview {
    VStack(alignment: .leading, spacing: 8) {
        ForEach([
            TunnelState.stopped, .starting, .running,
            .reconnecting, .stopping, .error
        ], id: \.self) { state in
            HStack {
                StatusBadge(state: state)
                StatusBadge(state: state, style: .compact)
            }
        }
    }
    .padding()
}
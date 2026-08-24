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
///
/// Animation strategy:TimelineView(`.periodic`) 而不是 `repeatForever`。
/// 之前每个 badge 一个 `@State pulse = true` + `.repeatForever` 动画 driver —
/// N 个 running tunnel = N 个独立 framerate 唤醒,hosting controller 在每个
/// animation tick 都重新评估 view tree。TimelineView 用一个共享的 date source
/// 调度,phase 直接从当前 Date 算出来 — 无 `@State`,无 driver,phase 全局同步。
/// `state` 切到非 .running 时,TimelineView 整块从 tree 里移除,不需要额外
/// "reset pulse" 逻辑(之前要靠 `@State pulse = true` 初始值 + 切换时不响应的
/// `.animation` modifier 凑合)。
private struct CompactStatusDot: View {
    let state: TunnelState
    var size: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = AppStatusColor.color(for: state)
        let isRunning = state == .running && !reduceMotion

        Group {
            if isRunning {
                TimelineView(.periodic(from: .now, by: 1.4 / 30.0)) { ctx in
                    let phase = Self.phase(at: ctx.date)
                    ZStack {
                        // Halo: opacity 0.55→0.12,scale 1.4→3.6 — 全程可见不归零,
                        // 保留绿色饱和度不被深色背景吃掉。
                        Circle()
                            .fill(color.opacity(0.55 - 0.43 * phase))
                            .frame(width: size, height: size)
                            .scaleEffect(1.4 + 2.2 * phase)
                        // Solid dot:opacity 1.0→0.6 — 与 halo 反向呼吸
                        Circle()
                            .fill(color.opacity(1.0 - 0.4 * phase))
                            .frame(width: size, height: size)
                    }
                }
            } else {
                // 非 .running:纯静态点。SwiftUI 直接挂载,无 TimelineView 开销。
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }

    /// 把当前时间映射到 0..1 相位,1.4s 一个 sin 周期 — 0→1→0 平滑往返。
    private static func phase(at date: Date) -> Double {
        let cycle: Double = 1.4
        let raw = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle) / cycle
        return sin(raw * .pi)
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
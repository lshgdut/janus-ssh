import SwiftUI
import JanusSSHTunnelEngine

/// Compact status indicator for tunnel lifecycle states.
///
/// Two visual modes:
/// - `.full`    — colored dot + label inside a tinted pill (default)
/// - `.compact` — colored dot only, suitable for tight rows (e.g. menu bar)
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
            Circle()
                .fill(AppStatusColor.color(for: state))
                .frame(width: 8, height: 8)
        case .full:
            HStack(spacing: 6) {
                Circle()
                    .fill(AppStatusColor.color(for: state))
                    .frame(width: 6, height: 6)
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

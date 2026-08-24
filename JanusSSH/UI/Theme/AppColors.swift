import SwiftUI
import JanusSSHTunnelEngine

/// Status colors for tunnel lifecycle states.
///
/// Six-state palette; the compiler forces an update here when a new
/// `TunnelState` case is added (no `default:` to silently swallow cases).
///
/// `.accentColor` is used for `.running` so the app inherits the user's
/// chosen accent color when a tunnel is healthy. The other five states
/// use stable semantic colors that don't shift with the system theme.
enum AppStatusColor {
    /// Tunnel is running normally — dedicated vivid green so the breathing
    /// halo holds saturation when scaled/faded on dark surfaces.
    /// (Previously inherited `.accentColor`, which on most systems is blue
    /// and washed out to gray once the halo opacity dropped.)
    static let connected: Color = Color(red: 0.20, green: 0.82, blue: 0.38)

    /// Tunnel is starting up.
    static let connecting: Color = .orange

    /// Tunnel is in the middle of an automatic reconnect.
    static let reconnecting: Color = .yellow

    /// Tunnel has errored.
    static let failed: Color = .red

    /// Tunnel is shutting down.
    static let disconnecting: Color = .gray

    /// Tunnel is idle / stopped.
    static let idle: Color = Color.secondary

    /// Resolve color from a `TunnelState`.
    static func color(for state: TunnelState) -> Color {
        switch state {
        case .running:
            return connected
        case .starting:
            return connecting
        case .reconnecting:
            return reconnecting
        case .error:
            return failed
        case .stopping:
            return disconnecting
        case .stopped:
            return idle
        }
    }
}

/// Semantic colors used across the app.
///
/// Distinguishes "intentional palette tokens" from raw SwiftUI primitives
/// (`.red`, `.white.opacity(0.1)`, …). Adding app-wide tokens here is the
/// preferred way to introduce a new color rather than inlining hex.
enum AppColors {
    /// Destructive actions (Reset, Stop All, Delete).
    static let destructive: Color = .red

    /// Subtle hover background on dark surfaces (menu bar).
    static let hoverSubtle: Color = Color.white.opacity(0.06)

    /// Subtle selection background on dark surfaces.
    static let selectionSubtle: Color = Color.white.opacity(0.1)

    /// Subtle red wash used behind destructive sections.
    static let destructiveSurface: Color = Color.red.opacity(0.05)

    /// Border used around destructive sections.
    static let destructiveBorder: Color = Color.red.opacity(0.5)
}

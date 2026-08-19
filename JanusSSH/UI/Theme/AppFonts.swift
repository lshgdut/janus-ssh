import SwiftUI

/// Typography helpers. Currently a thin wrapper around system fonts;
/// provides a single place to introduce custom fonts later (e.g. SF Mono
/// for log lines, Inter for body, …) without scattering font choices.
enum AppFonts {
    /// Monospaced font used for log entries and connection detail lines.
    static let monospacedCaption: Font = .system(.caption, design: .monospaced)
}

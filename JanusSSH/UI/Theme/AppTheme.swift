import SwiftUI

/// Top-level theme namespace. Intentionally minimal — most styling lives
/// on individual components. This exists so future SwiftUI environment
/// keys, configuration objects, or design-token dictionaries have a
/// stable home.
enum AppTheme {
    /// Standard corner radius for cards, dialogs, and menu surfaces.
    static let cornerRadius: CGFloat = 12

    /// Standard padding inside a card/section.
    static let sectionPadding: CGFloat = 16
}

import SwiftUI

/// Centered placeholder shown when a list has no items.
///
/// Used by screens like ProfileListView to invite the user to take action
/// (e.g. create the first profile) rather than presenting a blank surface.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String?

    /// - Parameters:
    ///   - systemImage: SF Symbol shown above the title.
    ///   - title: Primary heading (e.g. "No profiles yet").
    ///   - message: Optional secondary explanation. Hidden when nil.
    init(systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    EmptyStateView(
        systemImage: "tray",
        title: "No profiles yet",
        message: "Click + to create your first tunnel profile."
    )
}

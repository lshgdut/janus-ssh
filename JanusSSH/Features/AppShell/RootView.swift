import SwiftUI
import JanusSSHTunnelEngine

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @State private var selection: SidebarItem? = .profiles
    @State private var draftProfile: Profile?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch selection ?? .profiles {
                case .profiles:
                    ProfileListView()
                case .sshHosts:
                    SSHHostListView()
                case .settings:
                    SettingsView()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newProfileRequested)) { _ in
                openEditor(for: nil)
            }
        }
    }

    /// 用 openWindow 而不是 .sheet — 独立窗口可以自由调整大小,不会被 sheet 的固定尺寸截断
    private func openEditor(for profile: Profile?) {
        let draft: Profile
        if let p = profile {
            draft = p
        } else {
            draft = Profile(
                name: "",
                sshHostAlias: container.sshHostManager.hosts.first?.alias ?? "",
                forwards: [PortForward(localHost: "127.0.0.1", localPort: 0,
                                       remoteHost: "", remotePort: 0, label: nil)],
                behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        // 用 NotificationCenter 传递,跨窗口工作
        NotificationCenter.default.post(
            name: .openProfileEditor, object: nil, userInfo: ["profile": draft]
        )
    }
}

enum SidebarItem: Hashable {
    case profiles, sshHosts, settings
}

extension Notification.Name {
    static let openProfileEditor = Notification.Name("janus.openProfileEditor")
}
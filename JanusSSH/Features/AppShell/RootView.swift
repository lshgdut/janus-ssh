import SwiftUI
import JanusSSHTunnelEngine

struct RootView: View {
    @Environment(AppContainer.self) private var container
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
            .sheet(item: $draftProfile) { profile in
                ProfileEditorView(initial: profile)
            }
            .onReceive(NotificationCenter.default.publisher(for: .newProfileRequested)) { _ in
                draftProfile = Profile(
                    name: "",
                    sshHostAlias: container.sshHostManager.hosts.first?.alias ?? "",
                    forwards: [PortForward(localHost: "127.0.0.1", localPort: 0,
                                           remoteHost: "", remotePort: 0, label: nil)],
                    behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
        }
    }
}

enum SidebarItem: Hashable {
    case profiles, sshHosts, settings
}
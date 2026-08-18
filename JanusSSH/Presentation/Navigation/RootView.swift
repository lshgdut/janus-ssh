import SwiftUI

struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            DetailView()
        }
    }
}

enum SidebarItem: Hashable {
    case profiles, sshHosts, settings
}

struct DetailView: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: SidebarItem? = .profiles
    @State private var draftProfile: Profile?

    var body: some View {
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
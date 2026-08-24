import SwiftUI
import JanusSSHTunnelEngine

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @State private var selection: SidebarItem? = .profiles

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
                openEditor()
            }
        }
    }

    /// Cmd+N 走的入口:构造空 profile + openWindow
    /// 关键:SwiftUI WindowGroup 不会自动 mount,必须调用 openWindow(id:) 才会创建窗口实例
    /// container.requestEdit() 只是把 profile 写到 Observable state,
    /// ProfileEditorWindow 的 body 监听该 state 并显示对应编辑器
    private func openEditor() {
        let draft = Profile(
            name: "",
            sshHostAlias: container.sshHostManager.hosts.first?.alias ?? "",
            forwards: [PortForward(localHost: "127.0.0.1", localPort: 0,
                                   remoteHost: "127.0.0.1", remotePort: 0, label: nil)],
            behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
            createdAt: Date(),
            updatedAt: Date()
        )
        container.requestEdit(profile: draft, isNew: true)
        openWindow(id: "profile-editor")
    }
}

enum SidebarItem: Hashable {
    case profiles, sshHosts, settings
}
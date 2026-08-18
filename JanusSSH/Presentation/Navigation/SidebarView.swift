import SwiftUI

struct SidebarView: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: SidebarItem? = .profiles

    var body: some View {
        List(selection: $selection) {
            Section("导航") {
                Label("Profiles", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.profiles)
                Label("SSH Hosts", systemImage: "network")
                    .tag(SidebarItem.sshHosts)
                Label("Settings", systemImage: "gear")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
    }
}
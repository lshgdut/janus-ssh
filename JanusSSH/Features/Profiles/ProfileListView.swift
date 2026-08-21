import SwiftUI
import JanusSSHTunnelEngine

struct ProfileListView: View {
    @Environment(AppContainer.self) private var container
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Toolbar()
            if container.profiles.isEmpty {
                EmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProfiles) { profile in
                            ProfileCard(profile: profile,
                                        tunnel: container.tunnelManager.tunnel(for: profile.id))
                                .onTapGesture {
                                    openEditor(for: profile)
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar)
    }

    /// 不用 .sheet — 改用 openWindow 弹出独立窗口
    /// 原因:macOS sheet 尺寸固定,长内容会被截断;独立窗口可自由 resize
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
        container.requestEdit(profile: draft)
    }

    private var filteredProfiles: [Profile] {
        guard !searchText.isEmpty else { return container.profiles }
        let q = searchText.lowercased()
        return container.profiles.filter { p in
            p.name.lowercased().contains(q) ||
            p.sshHostAlias.lowercased().contains(q)
        }
    }
}

// MARK: - Toolbar

private struct Toolbar: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles").font(.title2).fontWeight(.semibold)
                Text("\(container.profiles.count) profiles")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                container.requestEdit(profile: Profile(
                    name: "",
                    sshHostAlias: container.sshHostManager.hosts.first?.alias ?? "",
                    forwards: [PortForward(localHost: "127.0.0.1", localPort: 0,
                                           remoteHost: "", remotePort: 0, label: nil)],
                    behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
                    createdAt: Date(),
                    updatedAt: Date()
                ))
            } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.background)
    }
}

// MARK: - Empty State

private struct EmptyState: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Profiles yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Create your first SSH tunnel profile to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                container.requestEdit(profile: Profile(
                    name: "",
                    sshHostAlias: container.sshHostManager.hosts.first?.alias ?? "",
                    forwards: [PortForward(localHost: "127.0.0.1", localPort: 0,
                                           remoteHost: "", remotePort: 0, label: nil)],
                    behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
                    createdAt: Date(),
                    updatedAt: Date()
                ))
            } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
// MARK: - Profile Card
private struct ProfileCard: View {
    let profile: Profile
    let tunnel: Tunnel?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.system(.title3, design: .default).weight(.semibold))
                HStack(spacing: 8) {
                    Text(profile.sshHostAlias)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let t = tunnel, t.pid != nil {
                        Text("PID \(t.pid ?? 0)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Text("\(profile.forwards.count) forwards")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var stateColor: Color {
        guard let t = tunnel else { return .gray.opacity(0.4) }
        switch t.state {
        case .running, .starting: return .green
        case .error: return .red
        case .stopping: return .orange
        case .stopped, .reconnecting: return .gray
        }
    }
}

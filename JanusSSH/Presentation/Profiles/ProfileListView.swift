import SwiftUI
import JanusSSHTunnelEngine

struct ProfileListView: View {
    @Environment(AppContainer.self) private var container
    @State private var searchText: String = ""
    @State private var editingProfile: Profile?

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
                                    editingProfile = profile
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar)
        .sheet(item: $editingProfile) { profile in
            ProfileEditorView(initial: profile)
        }
    }

    private var filteredProfiles: [Profile] {
        guard !searchText.isEmpty else { return container.profiles }
        let q = searchText.lowercased()
        return container.profiles.filter {
            $0.name.lowercased().contains(q) ||
            $0.sshHostAlias.lowercased().contains(q) ||
            $0.forwards.contains { String($0.localPort).contains(q) }
        }
    }
}

// MARK: - Toolbar

private struct Toolbar: View {
    @Environment(AppContainer.self) private var container
    @State private var newDraft: Profile?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles").font(.title2).fontWeight(.medium)
                let running = container.tunnelManager.tunnels.values.filter {
                    $0.state == .running || $0.state == .starting
                }.count
                Text("\(container.profiles.count) 个 Profile · \(running) 个运行中")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Stop All") { Task { await container.tunnelManager.stopAll() } }
                .buttonStyle(.bordered)
            Button("Start All") { Task { try? await container.tunnelManager.startAll() } }
                .buttonStyle(.bordered)
            Button {
                newDraft = Profile(name: "", sshHostAlias: container.sshHostManager.hosts.first?.alias ?? "",
                                   forwards: [PortForward(localHost: "127.0.0.1", localPort: 0,
                                                          remoteHost: "", remotePort: 0, label: nil)],
                                   behavior: Profile.Behavior(enabled: true, autoReconnect: true, autoStart: false),
                                   createdAt: Date(), updatedAt: Date())
            } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.background)
        .sheet(item: $newDraft) { p in ProfileEditorView(initial: p) }
    }
}

// MARK: - Empty State

private struct EmptyState: View {
    @Environment(AppContainer.self) private var container
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No profiles yet").font(.headline).foregroundStyle(.secondary)
            Text("Create your first SSH tunnel profile to get started.")
                .font(.subheadline).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("New Profile") {
                // Will be handled by toolbar
            }
            .buttonStyle(.borderedProminent)
            .hidden()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    let profile: Profile
    let tunnel: Tunnel?

    @Environment(AppContainer.self) private var container

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(profile.name).font(.title3).fontWeight(.medium)
                    StatusPill(state: tunnel?.state ?? .stopped)
                }
                HStack(spacing: 12) {
                    Text(profile.sshHostAlias)
                        .font(.system(.body, design: .monospaced))
                    Divider().frame(height: 12)
                    Text("\(profile.forwards.count) port forwards")
                }
                .font(.caption).foregroundStyle(.secondary)

                ForwardsPreview(forwards: profile.forwards)
                TagsRow(profile: profile)
            }
            Spacer()
            CardActions(profile: profile, tunnel: tunnel)
        }
        .padding(20)
        .background(.background)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(stateAccent)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }

    private var stateAccent: Color {
        switch tunnel?.state {
        case .running: return .accentColor
        case .error: return .red
        default: return .clear
        }
    }
}

private struct CardActions: View {
    let profile: Profile
    let tunnel: Tunnel?
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 8) {
            switch tunnel?.state {
            case .running:
                Button("Stop") {
                    Task { try? await container.tunnelManager.stop(profileID: profile.id) }
                }
                .buttonStyle(.bordered)
            case .starting, .starting:
                ProgressView().controlSize(.small)
            default:
                Button("Start") {
                    Task { try? await container.tunnelManager.start(profileID: profile.id) }
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                // Edit
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.borderless)
        }
        .frame(minWidth: 80)
    }
}

private struct ForwardsPreview: View {
    let forwards: [PortForward]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(forwards.prefix(3)) { f in
                HStack(spacing: 8) {
                    Text(f.localEndpoint)
                        .font(.system(.caption, design: .monospaced))
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    Text("\(f.remoteHost):\(f.remotePort)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let label = f.label {
                        Text(label)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if forwards.count > 3 {
                Text("+ \(forwards.count - 3) more")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct TagsRow: View {
    let profile: Profile
    var body: some View {
        HStack(spacing: 6) {
            if profile.behavior.autoReconnect {
                tag("auto-reconnect")
            }
            if profile.behavior.autoStart {
                tag("auto-start")
            }
            if !profile.behavior.enabled {
                tag("disabled", color: .red)
            }
        }
    }
    private func tag(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(color)
    }
}

struct StatusPill: View {
    let state: TunnelState
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .running: return .accentColor
        case .starting: return .orange
        case .reconnecting: return .yellow
        case .error: return .red
        case .stopping: return .gray
        case .stopped: return .secondary
        }
    }

    private var label: String {
        switch state {
        case .running: return "Running"
        case .starting: return "Starting"
        case .reconnecting: return "Reconnecting"
        case .error: return "Error"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        }
    }
}
import SwiftUI
import AppKit
import JanusSSHTunnelEngine

struct MenuBarView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            runningSection
            Divider()
            actions
        }
        .frame(width: 340)
        // 用 system 背景 + material,自动适配 light/dark
        .background(.regularMaterial)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(Color.accentColor)
            Text("janus-ssh").bold()
                .foregroundStyle(.primary)
            Spacer()
            let running = container.tunnelManager.tunnels.values.filter {
                $0.state == .running || $0.state == .starting
            }.count
            let error = container.tunnelManager.tunnels.values.filter { $0.state == .error }.count
            Text("\(running) running · \(error) error")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var runningSection: some View {
        Group {
            Text("Running").font(.caption).textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 8)
            ForEach(Array(container.profiles), id: \.id) { profile in
                if let tunnel = container.tunnelManager.tunnel(for: profile.id),
                   tunnel.state == .running || tunnel.state == .starting {
                    MenuBarProfileRow(profile: profile, tunnel: tunnel) {
                        Task { try? await container.tunnelManager.stop(profileID: profile.id) }
                    }
                }
            }
        }
    }

    private var actions: some View {
        Group {
            MenuBarItem(label: "Start All", shortcut: "⌥⌘S") {
                Task { try? await container.tunnelManager.startAll() }
            }
            MenuBarItem(label: "Stop All", shortcut: "⌥⌘X") {
                Task { await container.tunnelManager.stopAll() }
            }
            Divider()
            MenuBarItem(label: "Open Application", shortcut: "⌘1") {
                NSApp.activate(ignoringOtherApps: true)
                if let url = URL(string: "janusssh://main") {
                    NSWorkspace.shared.open(url)
                }
            }
            MenuBarItem(label: "Settings…", shortcut: "⌥⌘,") {
                if #available(macOS 14, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            MenuBarItem(label: "Refresh SSH Config", shortcut: "⌘R") {
                Task { await container.sshHostManager.refresh() }
            }
            Divider()
            MenuBarItem(label: "Quit", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct MenuBarProfileRow: View {
    let profile: Profile
    let tunnel: Tunnel
    let onAction: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onAction) {
            HStack(spacing: 12) {
                StatusBadge(state: tunnel.state, style: .compact)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.body)
                        .foregroundStyle(.primary)
                    Text("\(profile.forwards.count) forwards")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if hovering {
                    Text("Stop").font(.caption).foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(hovering ? Color.accentColor.opacity(0.15) : Color.clear)
        .onHover { hovering = $0 }
    }
}

private struct MenuBarItem: View {
    let label: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                Text(shortcut).foregroundStyle(.secondary).font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(hovering ? Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.15) : Color.clear)
        .onHover { hovering = $0 }
    }
}
import SwiftUI
import JanusSSHTunnelEngine

struct ProfileRunningView: View {
    @Environment(AppContainer.self) private var container
    let profile: Profile

    var body: some View {
        let tunnel = container.tunnelManager.tunnel(for: profile.id)
        HSplitView {
            // 左:Profile 详情
            VStack(alignment: .leading, spacing: 0) {
                header(tunnel: tunnel)
                Divider()
                forwardsSection
            }
            .frame(minWidth: 400)
            // 右:Logs
            TunnelLogView(profileID: profile.id)
                .frame(minWidth: 320, idealWidth: 480)
        }
    }

    private func header(tunnel: Tunnel?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profiles / \(profile.name)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(profile.name).font(.title).fontWeight(.medium)
                if let t = tunnel {
                    StatusBadge(state: t.state)
                    Text("PID \(t.pid ?? 0)").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            HStack(spacing: 12) {
                Text(profile.sshHostAlias)
                    .font(.system(.body, design: .monospaced))
                Divider().frame(height: 12)
                Text("\(profile.forwards.count) port forwards")
                if let t = tunnel {
                    Divider().frame(height: 12)
                    Text("uptime \(uptime(from: t.startedAt))")
                }
            }
            .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    Task { try? await container.tunnelManager.restart(profileID: profile.id) }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }.buttonStyle(.appSecondary)
                Button {
                    Task { try? await container.tunnelManager.stop(profileID: profile.id) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }.buttonStyle(.appSecondary)
                Button { } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(.appSecondary)
            }
        }
        .padding(20)
    }

    private var forwardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Forwards").font(.headline)
                Text("\(profile.forwards.count) of \(profile.forwards.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 16)

            VStack(spacing: 0) {
                ForEach(profile.forwards) { f in
                    HStack {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                        HStack(spacing: 8) {
                            Text(f.localEndpoint).font(.system(.body, design: .monospaced))
                            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                            Text(verbatim: "\(f.remoteHost):\(f.remotePort)")
                                .font(.system(.body, design: .monospaced))
                            if let label = f.label {
                                Text(label)
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        Spacer()
                        Text("latency 1.2ms").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.background)
                    Divider()
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
            .padding(.horizontal, 20).padding(.bottom, 20)

            Spacer()
        }
    }

    private func uptime(from start: Date?) -> String {
        guard let start = start else { return "—" }
        let s = Int(Date().timeIntervalSince(start))
        let h = s / 3600
        let m = (s % 3600) / 60
        return "\(h)h \(m)m"
    }
}
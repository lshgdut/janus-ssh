import SwiftUI
import JanusSSHTunnelEngine

struct SSHHostListView: View {
    @Environment(AppContainer.self) private var container
    @State private var searchText: String = ""
    @State private var testingAlias: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let err = container.sshHostManager.lastError {
                errorBanner(err)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredHosts) { host in
                        HostCard(host: host, testing: testingAlias == host.alias) {
                            testingAlias = host.alias
                            Task {
                                _ = await container.sshHostManager.test(alias: host.alias)
                                testingAlias = nil
                            }
                        }
                    }
                }
                .padding(20)
            }
            pathNote
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar)
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SSH Hosts").font(.title2).fontWeight(.medium)
                if let last = container.sshHostManager.lastRefreshed {
                    Text("\(container.sshHostManager.hosts.count) hosts · refreshed \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await container.sshHostManager.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.1))
            .foregroundStyle(.red)
    }

    private var pathNote: some View {
        Text("来源: ~/.ssh/config · 通过 ssh -G 解析 · 支持 Include · 应用不修改 SSH Config")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5))
    }

    private var filteredHosts: [SSHHost] {
        guard !searchText.isEmpty else { return container.sshHostManager.hosts }
        let q = searchText.lowercased()
        return container.sshHostManager.hosts.filter { h in
            h.alias.lowercased().contains(q) ||
            (h.user ?? "").lowercased().contains(q) ||
            (h.hostname ?? "").lowercased().contains(q)
        }
    }
}

private struct HostCard: View {
    let host: SSHHost
    let testing: Bool
    let onTest: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(host.alias).font(.system(.title3, design: .monospaced)).fontWeight(.medium)
                }
                Text("\(host.user ?? "?")@\(host.hostname ?? "?"):\(host.port ?? 22)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    if !host.identityFiles.isEmpty {
                        Detail(k: "IdentityFile", v: host.identityFiles.first ?? "")
                    }
                    if let pj = host.proxyJump {
                        Detail(k: "ProxyJump", v: pj)
                    }
                    if let sa = host.serverAliveInterval {
                        Detail(k: "ServerAlive", v: "\(sa)")
                    }
                }
            }
            Spacer()
            Button(action: onTest) {
                if testing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Test Connection", systemImage: "checkmark.circle")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }
}

private struct Detail: View {
    let k: String
    let v: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption2).textCase(.uppercase).foregroundStyle(.tertiary)
            Text(v).font(.system(.caption, design: .monospaced))
        }
    }
}
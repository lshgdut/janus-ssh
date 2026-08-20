import SwiftUI
import AppKit
import JanusSSHTunnelEngine

/// SSH Hosts 列表页 — 紧凑卡片 + 单色信息网格
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
            if container.sshHostManager.hosts.isEmpty && container.sshHostManager.lastRefreshed == nil {
                emptyState
            } else {
                hostList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索 Host / 用户 / 主机")
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SSH Hosts").font(.title2).fontWeight(.semibold)
                if let last = container.sshHostManager.lastRefreshed {
                    HStack(spacing: 6) {
                        Text("\(container.sshHostManager.hosts.count) hosts")
                            .font(.caption).foregroundStyle(.secondary)
                        Circle().fill(.secondary).frame(width: 2, height: 2)
                        Text("刷新于 \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                Task { await container.sshHostManager.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("未发现 SSH Host")
                .font(.headline).foregroundStyle(.secondary)
            Text("请检查 ~/.ssh/config 路径")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .background(.orange.opacity(0.08))
    }

    // MARK: - Host list

    private var hostList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredHosts) { host in
                    HostCard(
                        host: host,
                        container: container,
                        testing: testingAlias == host.alias,
                        onTest: { testConnection(alias: host.alias) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
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

    private func testConnection(alias: String) {
        testingAlias = alias
        Task {
            _ = await container.sshHostManager.test(alias: alias)
            testingAlias = nil
        }
    }
}

// MARK: - Host card

private struct HostCard: View {
    let host: SSHHost
    let container: AppContainer
    let testing: Bool
    let onTest: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: alias + status + actions
            HStack(alignment: .center, spacing: 12) {
                HostStatusBadge(result: container.sshHostManager.result(for: host.alias))
                Text(host.alias)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                if let pj = host.proxyJump {
                    ProxyChip(name: pj)
                }
                Spacer()
                TestButton(
                    testing: testing,
                    result: container.sshHostManager.result(for: host.alias),
                    action: onTest
                )
            }

            // Connection line: user@host:port
            HStack(spacing: 6) {
                Text("\(host.user ?? "—")@\(host.hostname ?? "—")")
                    .font(.system(.body, design: .monospaced))
                if let port = host.port {
                    Text(":")
                        .foregroundStyle(.tertiary)
                        .font(.system(.body, design: .monospaced))
                    Text("\(port)")
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
            }

            // Detail grid: compact 2-column field list
            if hasDetails {
                DetailGrid(host: host)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(hovering ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15),
                              lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    private var hasDetails: Bool {
        !host.identityFiles.isEmpty
            || host.proxyJump != nil
            || host.forwardAgent != nil
            || host.serverAliveInterval != nil
    }
}

// MARK: - Status badge

private struct HostStatusBadge: View {
    let result: SSHHostManager.TestResult?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        guard let r = result else { return .gray.opacity(0.4) }
        switch r.outcome {
        case .reachable: return .green
        case .unreachable: return .red
        case .timeout: return .orange
        }
    }
}

// MARK: - Proxy chip

private struct ProxyChip: View {
    let name: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
            Text("via \(name)")
                .font(.caption2)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(.orange.opacity(0.12))
        )
    }
}

// MARK: - Test button

private struct TestButton: View {
    let testing: Bool
    let result: SSHHostManager.TestResult?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button(action: action) {
                HStack(spacing: 6) {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: iconName)
                            .imageScale(.small)
                            .foregroundStyle(iconColor)
                    }
                    Text(label).foregroundStyle(labelColor)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(testing)

            if let r = result, !testing {
                Text(detail(for: r))
                    .font(.caption2)
                    .foregroundStyle(detailColor(for: r))
            }
        }
    }

    private var iconName: String {
        guard let r = result else { return "bolt.horizontal" }
        switch r.outcome {
        case .reachable: return "checkmark.circle.fill"
        case .unreachable: return "xmark.circle.fill"
        case .timeout: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        guard let r = result else { return .secondary }
        switch r.outcome {
        case .reachable: return .green
        case .unreachable: return .red
        case .timeout: return .orange
        }
    }

    private var label: String {
        guard let r = result else { return "Test" }
        switch r.outcome {
        case .reachable: return "Tested"
        case .unreachable: return "Retry"
        case .timeout: return "Timeout"
        }
    }

    private var labelColor: Color {
        guard let r = result else { return .primary }
        switch r.outcome {
        case .reachable: return .green
        case .unreachable: return .red
        case .timeout: return .orange
        }
    }

    private func detail(for r: SSHHostManager.TestResult) -> String {
        let timeAgo = r.testedAt.formatted(.relative(presentation: .named))
        switch r.outcome {
        case .reachable: return "成功 · \(timeAgo)"
        case .unreachable(let reason): return "失败 · \(reason) · \(timeAgo)"
        case .timeout: return "超时 · \(timeAgo)"
        }
    }

    private func detailColor(for r: SSHHostManager.TestResult) -> Color {
        switch r.outcome {
        case .reachable: return .secondary
        default: return .red.opacity(0.85)
        }
    }
}

// MARK: - Detail grid

private struct DetailGrid: View {
    let host: SSHHost
    var body: some View {
        // 用 HStack 网格展示字段(简单两列布局,避免 Grid 复杂度)
        VStack(alignment: .leading, spacing: 4) {
            if let pj = host.proxyJump {
                HostFieldLabel("ProxyJump", value: pj)
            }
            if !host.identityFiles.isEmpty {
                HostFieldLabel("IdentityFile", value: host.identityFiles.first ?? "")
            }
            if host.forwardAgent == true {
                HostFieldLabel("ForwardAgent", value: "yes")
            } else if host.forwardAgent == false {
                HostFieldLabel("ForwardAgent", value: "no")
            }
            if let sa = host.serverAliveInterval {
                HostFieldLabel("ServerAlive", value: "\(sa)s")
            }
        }
    }
}

private struct HostFieldLabel: View {
    let title: String
    let value: String
    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
    }
}

// MARK: - SSHHost extensions for view

private extension SSHHost {
    /// 单 host 的测试结果 + 时间
    struct TestState: Equatable {
        let reachable: Bool?
        let lastTested: Date?
        static let unknown = TestState(reachable: nil, lastTested: nil)
    }

    var testResult: TestState {
        // 由 SSHHostManager 注入;此处先返回 unknown
        .unknown
    }

    /// "via X" / "used by X" 之类的关系描述
    var relationship: String? {
        // 由 SSHHostManager 注入;此处返回 nil
        nil
    }
}
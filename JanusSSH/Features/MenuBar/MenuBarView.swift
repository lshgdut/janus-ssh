import SwiftUI
import AppKit
import JanusSSHTunnelEngine

/// macOS MenuBarExtra popover(.window 模式)— 完全用 SwiftUI 自定义渲染,
/// 对齐设计稿:深色 material、蓝 S 角标、profile 行带状态点和 hover 动作。
struct MenuBarView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme

    private let popoverWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            activeSection
            if !errorProfiles.isEmpty {
                divider
                errorSection
            }
            divider
            actions
        }
        .frame(width: popoverWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator, lineWidth: 0.5)
        )
        .padding(4)  // 给 material 一点呼吸空间,让外框不贴边
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            BrandBadge()
            Text("JANUS-SSH")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            statusCounts
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var statusCounts: some View {
        let running = container.tunnelManager.tunnels.values.filter {
            $0.state == .running || $0.state == .starting || $0.state == .reconnecting
        }.count
        let error = container.tunnelManager.tunnels.values.filter { $0.state == .error }.count
        return HStack(spacing: 6) {
            Text("\(running) running")
            Text("·").foregroundStyle(.tertiary)
            Text("\(error) error")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    // MARK: - Profile collections

    private var activeProfiles: [(Profile, Tunnel)] {
        container.profiles.compactMap { profile in
            guard let t = container.tunnelManager.tunnel(for: profile.id) else { return nil }
            switch t.state {
            case .running, .starting, .reconnecting, .stopping:
                return (profile, t)
            case .stopped, .error:
                return nil
            }
        }
    }

    private var errorProfiles: [(Profile, Tunnel)] {
        container.profiles.compactMap { profile in
            guard let t = container.tunnelManager.tunnel(for: profile.id),
                  t.state == .error else { return nil }
            return (profile, t)
        }
    }

    // MARK: - Sections

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Running")
            if activeProfiles.isEmpty {
                emptyHint("No active tunnels")
            } else {
                ForEach(Array(activeProfiles.enumerated()), id: \.element.0.id) { idx, pair in
                    if idx > 0 { rowDivider }
                    MenuBarProfileRow(profile: pair.0, tunnel: pair.1)
                }
            }
        }
    }

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Issues", color: .red)
            ForEach(Array(errorProfiles.enumerated()), id: \.element.0.id) { idx, pair in
                if idx > 0 { rowDivider }
                MenuBarProfileRow(profile: pair.0, tunnel: pair.1)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 0) {
            MenuBarItem(label: "Start All", shortcut: "⌥⌘S") {
                Task { try? await container.tunnelManager.startAll() }
            }
            MenuBarItem(label: "Stop All", shortcut: "⌥⌘X") {
                Task { await container.tunnelManager.stopAll() }
            }
            rowDivider
            MenuBarItem(label: "Open Application", shortcut: "⌘1") {
                NSApp.activate(ignoringOtherApps: true)
                if let url = URL(string: "janusssh://main") {
                    NSWorkspace.shared.open(url)
                }
            }
            MenuBarItem(label: "Settings…", shortcut: "⌘,") {
                if #available(macOS 14, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            MenuBarItem(label: "Refresh SSH Config", shortcut: "⌘R") {
                Task { await container.sshHostManager.refresh() }
            }
            rowDivider
            MenuBarItem(label: "Quit", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Building blocks

    /// Section 之间的分割线(header ↔ running ↔ actions)
    private var divider: some View {
        Rectangle()
            .fill(.separator.opacity(0.6))
            .frame(height: 1)
            .padding(.horizontal, 8)
    }

    /// profile 行之间的细分割线
    private var rowDivider: some View {
        Rectangle()
            .fill(.separator.opacity(0.4))
            .frame(height: 1)
            .padding(.leading, 22)  // 缩进对齐 profile 名
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, color: Color = .secondary) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

// MARK: - Brand badge

private struct BrandBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
            Text("S")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Profile row

private struct MenuBarProfileRow: View {
    @Environment(AppContainer.self) private var container
    let profile: Profile
    let tunnel: Tunnel
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: performAction) {
            HStack(spacing: 10) {
                StatusBadge(state: tunnel.state, style: .compact)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(metadata)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if hovering {
                    Text(actionLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(actionColor)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.12) : .clear)
                .padding(.horizontal, 6)
        )
        .onHover { hovering = $0 }
    }

    private var actionLabel: String {
        switch tunnel.state {
        case .running, .starting, .reconnecting, .stopping: return "Stop"
        case .error: return "Retry"
        case .stopped: return "Start"
        }
    }

    private var actionColor: Color {
        switch tunnel.state {
        case .error: return .red
        case .stopped: return Color.accentColor
        default: return .secondary
        }
    }

    private var metadata: String {
        let forwardCount = profile.forwards.count
        let forwardStr = "\(forwardCount) \(forwardCount == 1 ? "forward" : "forwards")"

        switch tunnel.state {
        case .running, .reconnecting:
            if let started = tunnel.startedAt {
                return "\(forwardStr) · \(Self.uptime(from: started))"
            }
            return forwardStr
        case .starting:
            return "\(forwardStr) · connecting…"
        case .stopping:
            return "\(forwardStr) · disconnecting…"
        case .error:
            return tunnel.lastError.map(Self.describe) ?? "error"
        case .stopped:
            return forwardStr
        }
    }

    private func performAction() {
        Task {
            switch tunnel.state {
            case .running, .starting, .reconnecting, .stopping:
                try? await container.tunnelManager.stop(profileID: profile.id)
            case .error, .stopped:
                try? await container.tunnelManager.start(profileID: profile.id)
            }
        }
    }

    // MARK: helpers

    private static func uptime(from start: Date) -> String {
        let s = Int(Date().timeIntervalSince(start))
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    private static func describe(_ err: TunnelError) -> String {
        switch err {
        case .networkUnreachable(let host):       return "unreachable · \(host)"
        case .authenticationFailed(let host):     return "auth failed · \(host)"
        case .sshConfigResolutionFailed(let host): return "config failed · \(host)"
        case .localPortUnavailable(let port):     return "port \(port) in use"
        case .sshBinaryNotFound:                  return "ssh binary not found"
        case .sshSpawnFailed:                     return "spawn failed"
        case .sshExited(let code, _, _):          return "exited \(code)"
        default:                                  return "error"
        }
    }
}

// MARK: - Menu item

private struct MenuBarItem: View {
    let label: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.12) : .clear)
                .padding(.horizontal, 6)
        )
        .onHover { hovering = $0 }
    }
}
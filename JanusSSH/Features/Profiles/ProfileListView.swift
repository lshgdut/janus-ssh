import SwiftUI
import JanusSSHTunnelEngine

struct ProfileListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(searchText: $searchText)
            if container.profiles.isEmpty {
                EmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProfiles) { profile in
                            ProfileCard(profile: profile,
                                        tunnel: container.tunnelManager.tunnel(for: profile.id))
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 用 WindowGroup + openWindow 弹出独立编辑器
    /// 不用 .sheet — sheet 尺寸固定,长内容会被截断;独立窗口可自由 resize
    /// SwiftUI WindowGroup 不会自动 mount,必须 openWindow(id:) 才会创建窗口实例
    private func openEditor(for profile: Profile) {
        container.requestEdit(profile: profile)
        openWindow(id: "profile-editor")
    }

    private var filteredProfiles: [Profile] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return container.profiles }
        return container.profiles.filter { p in
            if p.name.lowercased().contains(q) { return true }
            if p.sshHostAlias.lowercased().contains(q) { return true }
            // 端口号搜索 — 任意一条 forward 的本地或远程端口匹配即可
            for fwd in p.forwards {
                if String(fwd.localPort).contains(q) { return true }
                if String(fwd.remotePort).contains(q) { return true }
            }
            return false
        }
    }
}

// MARK: - Toolbar

private struct Toolbar: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @Binding var searchText: String

    private var runningCount: Int {
        container.tunnelManager.tunnels.values.filter {
            $0.state == .running || $0.state == .starting
        }.count
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                // 左:标题 + 计数 pill — 固定自然宽度,窗口缩窄时让搜索框先被挤压
                HStack(spacing: 12) {
                    Text("Profiles")
                        .font(.system(.title, design: .default).weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: true, vertical: false)
                    CountPill(total: container.profiles.count, running: runningCount)
                }
                .fixedSize(horizontal: true, vertical: false)

                // 中:搜索框 — 唯一会缩的 element,缩到 0 也允许(用户可以靠 Cmd+F)
                SearchField(text: $searchText,
                            placeholder: "搜索 Profile、SSH Host 或 Port")
                    .frame(maxWidth: 360)
                    .layoutPriority(0)

                Spacer(minLength: 0)

                // 右:动作按钮 — 固定自然宽度,搜索框挤压时不会被 shrink
                HStack(spacing: 8) {
                    Button("Stop All") {
                        Task { await container.tunnelManager.stopAll() }
                    }
                    .buttonStyle(.appSecondary)
                    .disabled(runningCount == 0)

                    Button("Start All") {
                        Task { try? await container.tunnelManager.startAll() }
                    }
                    .buttonStyle(.appSecondary)
                    .disabled(container.profiles.isEmpty || runningCount > 0)

                    Button {
                        openEditor()
                    } label: {
                        Label("New Profile", systemImage: "plus")
                    }
                    .buttonStyle(.appPrimary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.background)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func openEditor() {
        let draft = container.makeBlankDraftProfile()
        container.requestEdit(profile: draft, isNew: true)
        openWindow(id: "profile-editor")
    }
}

// MARK: - Count Pill

private struct CountPill: View {
    let total: Int
    let running: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(running > 0 ? Color.blue : Color.gray)
                .frame(width: 6, height: 6)
            Text("\(total) 个 Profile · \(running) 个运行中")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Search Field

private struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Empty State

private struct EmptyState: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

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
                openEditor()
            } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(.appPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openEditor() {
        let draft = container.makeBlankDraftProfile()
        container.requestEdit(profile: draft, isNew: true)
        openWindow(id: "profile-editor")
    }
}

// MARK: - Profile Card

private struct ProfileCard: View {
    let profile: Profile
    let tunnel: Tunnel?
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @State private var now: Date = Date()
    @State private var showDeleteConfirm: Bool = false
    @State private var hovering = false

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左侧 3px accent bar — 状态色
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 10) {
                // 标题行:profile 名 + 状态 pill — pill 紧贴 title,不再右侧 Spacer 推开
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(profile.name)
                        .font(.system(.title3, design: .default).weight(.semibold))
                    StatusPill(tunnel: tunnel)
                }

                // metadata 行:host · N forwards · uptime
                metadataRow

                // forwards 列表(灰色背景)
                if !profile.forwards.isEmpty {
                    forwardsList
                }

                // 底部 tags
                tagsRow
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧:主操作 + 显式编辑/删除菜单
            // 不要整体点击进编辑 — 容易误触;显式菜单更清晰
            VStack(alignment: .trailing, spacing: 10) {
                actionButton
                CardMenu(
                    onEdit: { openEditor() },
                    onDelete: { showDeleteConfirm = true }
                )
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    hovering ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor),
                    lineWidth: hovering ? 1 : 0.5
                )
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .confirmationDialog(
            "Delete \"\(profile.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                Task { await container.deleteProfile(profile.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop the tunnel if running and remove the profile permanently.")
        }
        .onReceive(tick) { now = $0 }
    }

    private func openEditor() {
        container.requestEdit(profile: profile)
        openWindow(id: "profile-editor")
    }

    // MARK: - metadata row

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Text(profile.sshHostAlias)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            // 用 dot 分隔(与全 App 其它位置一致 — MenuBar / Sidebar / CountPill 都用 `·`)
            // 之前用 | 分隔显得跟系统其它文案不统一
            Text("·").foregroundStyle(.tertiary)
            Text("\(profile.forwards.count) port forwards")
                .font(.caption).foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            uptimeOrLastStarted
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var uptimeOrLastStarted: some View {
        if let started = tunnel?.startedAt, isRunning {
            Text("uptime \(format(duration: now.timeIntervalSince(started)))")
        } else if let started = tunnel?.startedAt {
            Text("last started \(format(relative: now.timeIntervalSince(started))) ago")
        } else {
            Text("never started")
        }
    }

    // MARK: - forwards list

    private var forwardsList: some View {
        VStack(spacing: 4) {
            ForEach(Array(profile.forwards.prefix(3).enumerated()), id: \.element.id) { _, fwd in
                ForwardLine(forward: fwd, isError: isError)
            }
            if profile.forwards.count > 3 {
                HStack {
                    Spacer()
                    Text("+\(profile.forwards.count - 3) more")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.06))
        )
    }

    // MARK: - tags row

    @ViewBuilder
    private var tagsRow: some View {
        HStack(spacing: 6) {
            if profile.behavior.autoReconnect {
                Tag(text: "auto-reconnect", color: .secondary)
            }
            if profile.behavior.autoStart {
                Tag(text: "auto-start", color: .secondary)
            }
            if isError, case .sshExited(let code, _, _) = tunnel?.lastError {
                Tag(text: "exit code \(code)", color: .red)
            }
            if !profile.behavior.enabled {
                Tag(text: "disabled", color: .secondary)
            } else if !profile.behavior.autoReconnect && !profile.behavior.autoStart && !isError {
                Tag(text: "enabled", color: .secondary)
            }
            Spacer()
        }
    }

    // MARK: - action button

    @ViewBuilder
    private var actionButton: some View {
        switch tunnel?.state {
        case .running, .starting, .reconnecting:
            Button("Stop") {
                Task { try? await container.tunnelManager.stop(profileID: profile.id) }
            }
            .buttonStyle(SecondaryButtonStyle())
        case .stopping:
            // 正在 stop 中,保持按钮可点但 action 幂等(重复 stop 由 TunnelManager 内部去重)
            Button("Stop") {
                Task { try? await container.tunnelManager.stop(profileID: profile.id) }
            }
            .buttonStyle(SecondaryButtonStyle())
        case .error:
            Button("Retry") {
                Task { try? await container.tunnelManager.start(profileID: profile.id) }
            }
            .buttonStyle(PrimaryButtonStyle())
        case nil, .stopped:
            Button("Start") {
                Task { try? await container.tunnelManager.start(profileID: profile.id) }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - state

    private var accentColor: Color {
        guard let t = tunnel else { return Color.gray.opacity(0.3) }
        switch t.state {
        case .running, .starting: return .blue
        case .reconnecting: return .orange
        case .error: return .red
        case .stopping: return .orange
        case .stopped: return Color.gray.opacity(0.3)
        }
    }

    private var isRunning: Bool {
        guard let s = tunnel?.state else { return false }
        return s == .running || s == .starting
    }

    private var isError: Bool {
        tunnel?.state == .error
    }

    private func format(duration: TimeInterval) -> String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    private func format(relative: TimeInterval) -> String {
        let total = Int(relative)
        let d = total / 86400
        let h = (total % 86400) / 3600
        if d > 0 { return "\(d) day\(d == 1 ? "" : "s")" }
        if h > 0 { return "\(h)h" }
        let m = total / 60
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }
}

// MARK: - Forward line

private struct ForwardLine: View {
    let forward: PortForward
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(forward.localHost):\(forward.localPort) → \(forward.remoteHost):\(forward.remotePort)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isError ? Color.red : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let label = forward.label, !label.isEmpty {
                // 标签用小 pill,跟正向行视觉绑定更紧 — 之前裸文字太安静
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.secondary.opacity(0.12))
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Error description

/// 把 TunnelError 智能映射成可读文案
/// 设计图示例:`Error · exit code 255` / `Error · Connection refused`
private func errorDescription(for t: Tunnel) -> String {
    guard let err = t.lastError else { return "Error" }
    switch err {
    case .sshExited(let code, _, _):
        return "Error · exit code \(code)"
    case .localPortUnavailable(let port):
        return "Error · port \(port) in use"
    case .hostUnknown(let host):
        return "Error · host \(host) not found"
    case .sshConfigResolutionFailed(let host):
        return "Error · ssh config invalid for \(host)"
    case .authenticationFailed(let host):
        return "Error · auth failed for \(host)"
    case .networkUnreachable(let host):
        return "Error · network unreachable \(host)"
    case .duplicateLocalPort(let port):
        return "Error · duplicate port \(port)"
    case .crossProfileLocalPortConflict(let port, _):
        return "Error · port \(port) conflict"
    case .profileNotFound, .sshBinaryNotFound, .sshSpawnFailed:
        return "Error"
    }
}

// MARK: - Status pill

private struct StatusPill: View {
    let tunnel: Tunnel?

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private var color: Color {
        guard let t = tunnel else { return .gray }
        switch t.state {
        case .running: return .blue
        case .starting: return .blue
        case .reconnecting: return .orange
        case .error: return .red
        case .stopping: return .orange
        case .stopped: return .gray
        }
    }

    private var text: String {
        guard let t = tunnel else { return "Stopped" }
        switch t.state {
        case .running:
            if let pid = t.pid { return "Running · PID \(pid)" }
            return "Running"
        case .starting: return "Starting"
        case .reconnecting: return "Reconnecting"
        case .error:
            return errorDescription(for: t)
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        }
    }
}

// MARK: - Tag

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.1))
            )
    }
}

// MARK: - Tiny "·" separator

private struct Separator: View {
    var body: some View {
        Text("·").font(.caption).foregroundStyle(.tertiary)
    }
}

// MARK: - Card menu (•••) — 显式编辑入口

private struct CardMenu: View {
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit Profile…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Profile…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Edit or delete this profile")
    }
}
// MARK: - Previews
// Xcode canvas 直接渲染 ProfileListView,改卡片 / hover / 按钮样式立刻看到反馈。
// AppContainer.preview 已经塞了 Production (running 2h) / Staging (running 1h) /
// Private Server (error unreachable) 三种状态,覆盖 ProfileCard 全视觉。

#if DEBUG
#Preview("ProfileList — populated") {
    ProfileListView()
        .environment(AppContainer.preview)
        .frame(width: 900, height: 700)
}

#Preview("ProfileList — empty") {
    // 空状态单独预览 — 用一个没有任何 profile 的 container
    EmptyPreviewContainer()
}
#endif

#if DEBUG
/// 空状态 preview — 直接给一个空 container
private struct EmptyPreviewContainer: View {
    @State private var container = AppContainer()
    var body: some View {
        ProfileListView()
            .environment(container)
            .frame(width: 900, height: 700)
    }
}
#endif

import SwiftUI
import AppKit
import JanusSSHTunnelEngine

/// macOS MenuBarExtra popover(.window 模式)— 完全用 SwiftUI 自定义渲染,
/// 对齐设计稿:深色 material、蓝 S 角标、profile 行带状态点和 hover 动作。
struct MenuBarView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings

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
            // 用 SwiftUI 标准 environment — 之前用 janusssh:// URL scheme
            // 没在 Info.plist 注册,NSWorkspace.open 静默失败。
            //
            MenuBarItem(label: "Open Application", shortcut: "⌘1") {
                debugLog("MenuBar action: Open Application fired")
                Task { @MainActor in
                    NSApp.activate(ignoringOtherApps: true)
                    AppWindowFocus.focusMain()
                }
                // 焦点切到主窗口 — popover 不再有用,主动 dismiss 避免屏幕上
                // 短暂同时有 menu + main 两个窗口。
                container.menuBarController.dismissPopover()
            }
            // 用 \.openSettings — 之前 NSApp.sendAction(showSettingsWindow:)
            // 从 MenuBarExtra 触发不稳定。
            MenuBarItem(label: "Settings…", shortcut: "⌘,") {
                debugLog("MenuBar action: Settings fired")
                openSettings()
                // openSettings 立即触发 SwiftUI Window scene,但 SettingsWindow
                // 实际浮现有一拍延迟。这里主动 dismiss popover,避免屏幕上短暂
                // 同时有两个 menu / settings 浮窗,以及 popover 残留把后续事件
                // 抢走的情况。
                container.menuBarController.dismissPopover()
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuBarItem(label: "Refresh SSH Config", shortcut: "⌘R") {
                debugLog("MenuBar action: Refresh SSH Config fired")
                Task { await container.sshHostManager.refresh() }
                // 刷新是后台操作,用户大概率想看到反馈 — 关掉 popover 让主窗口
                // 顶上来显示刷新的 hosts。
                container.menuBarController.dismissPopover()
            }
            rowDivider
            MenuBarItem(label: "Quit", shortcut: "⌘Q") {
                debugLog("MenuBar action: Quit fired")
                // 走 menuBarController.quit() — 它会显式拆 outside-click monitor +
                // 关 popover 再 NSApp.terminate。原来这里直接 NSApp.terminate(nil),
                // 依赖 outside-click monitor 副作用来 dismiss popover,但
                // .applicationDefined + NSHostingController 组合下偶发 popover
                // 残留,把 willTerminate 拖住,app 就不退出了。
                container.menuBarController.quit()
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
            // 设计稿:RUNNING 上下都有明显呼吸空间
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
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
        // 不用 `Button(action: performAction)` — 跟 MenuBarItem 同样的 SwiftUI
        // Button + .applicationDefined NSPopover 不接事件问题,改用 .onTapGesture
        // 走 SwiftUI gesture 系统。详见 MenuBarItem 注释。
        HStack(spacing: 10) {
            StatusBadge(state: tunnel.state, style: .compact)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    // 设计稿:profile 名用 regular 字重,不要 medium/bold
                    // 整体感觉更轻盈、更克制
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(metadata)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if hovering {
                // pending 状态(action 已经在跑)显示 spinner,而不是再显示
                // "Stop" / "Retry" —— 避免用户重复点击触发竞态。
                if isPending {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                } else if let label = actionLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(actionColor)
                        .transition(.opacity)
                }
            }
        }
        // 设计稿:profile 行上下留 ~9pt 呼吸空间,不要挤
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())  // 整行可点
        .hoverHighlight(hovering)
        // onHover 推到下一个 runloop tick — 鼠标若正好停在 row 上、popover
        // 一出现 .onHover 会立刻 fire,直接改 hovering 撞上 AppKit 的
        // window install-layout pass,触发 layoutSubtreeIfNeeded recursion warning。
        .onHover { h in
            Task { @MainActor in hovering = h }
        }
        .animation(.easeOut(duration: 0.08), value: hovering)
        // .allowsHitTesting(isPending ? false : true) 替代 .disabled — .disabled
        // 在某些 popover 上下文里会切掉 SwiftUI gesture 通道,改用 hit-testing
        // gate 保留 onTapGesture 一定能收事件。
        .allowsHitTesting(!isPending)
        .onTapGesture {
            if !isPending {
                debugLog("MenuBarProfileRow.onTapGesture fired: \(profile.name) state=\(tunnel.state)")
                performAction()
            }
        }
    }

    /// Action 正在执行的过渡状态 — stop 已发出但 SSH 还没退出 / start 已发出但
    /// tunnel 还没 connected / reconnect 还在重试中。这些状态下:
    ///   - 整行 Button 禁用(避免重复触发)
    ///   - action 区显示 spinner 而不是 "Stop" 文字
    private var isPending: Bool {
        switch tunnel.state {
        case .starting, .reconnecting, .stopping: return true
        case .running, .error, .stopped:          return false
        }
    }

    /// 给非 pending 状态的 row 显示的操作文本。pending 状态(.starting /
    /// .reconnecting / .stopping)返回 nil — caller 用 spinner 占位。
    private var actionLabel: String? {
        switch tunnel.state {
        case .running: return "Stop"
        case .error:   return "Retry"
        case .stopped: return "Start"
        case .starting, .reconnecting, .stopping: return nil
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
        // 防御:即使 .disabled 因为某些原因被绕过,这里也再卡一次
        guard !isPending else { return }
        Task {
            switch tunnel.state {
            case .running:
                try? await container.tunnelManager.stop(profileID: profile.id)
            case .error, .stopped:
                try? await container.tunnelManager.start(profileID: profile.id)
            case .starting, .reconnecting, .stopping:
                return  // pending,不该到这里
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

    var body: some View {
        // 不用 `Button(action: action)` — .applicationDefined NSPopover + SwiftUI
        // Button 这个组合下,Button 内部的 tap-gesture hit-test 在某些 macOS
        // 版本不接事件(实测监测到 clicks 落进 popover window,event.window match,
        // 但 Button action closure 永远不 fire — /tmp/janus-debug log 印证)。
        // 改用纯 HStack + .onTapGesture 走 SwiftUI gesture 系统,这个路径稳。
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        // 设计稿:menu item 上下 ~9pt 呼吸,与 profile 行保持节奏一致
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // hover 高亮作为 background — SwiftUI 的 .background
        // 会自动按 View 的实际尺寸渲染,而不是 label 的尺寸
        .hoverHighlight(hovering)
        .onHover { hovering = $0 }
        .onTapGesture {
            debugLog("MenuBarItem.onTapGesture fired: \(label)")
            action()
        }
    }
}
// 在 Xcode canvas 里直接预览 MenuBar 效果,改 padding / 字号 / hover 立刻看到反馈,
// 不需要跑 App + 点 menu bar 图标。
// 注意:Preview 里启动 AppContainer 会走完整 init(包括 sshConfigProvider 等),
// 对纯 UI 调整无害;真正加载 profiles / sweep 都在 .bootstrap() 里,而 preview
// 走的是 .preview,只调 seedPreviewProfiles()。

#if DEBUG
#Preview("MenuBar — light, with profiles") {
    MenuBarView()
        .environment(AppContainer.preview)
        .frame(width: 320)
        .preferredColorScheme(.light)
}

#Preview("MenuBar — dark, with profiles") {
    MenuBarView()
        .environment(AppContainer.preview)
        .frame(width: 320)
        .preferredColorScheme(.dark)
}
#endif

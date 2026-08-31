import SwiftUI
import AppKit
import JanusSSHTunnelEngine

/// macOS MenuBarExtra popover(.window 模式)— SwiftUI scene 自己渲染 panel,
/// 内容是纯 SwiftUI 树:header + running profile 行 + actions,
/// 对齐设计稿:蓝 S 角标、profile 行带状态点和 hover 动作。
///
/// 视觉:
///   - 系统 panel 自带轻量半透明背景(浅/深模式都自动反色),不要再叠
///     .background(.regularMaterial) — 双重材质会变灰蒙蒙。
///   - 不画自定义外框圆角/stroke — MenuBarExtra 系统 panel 已经处理好。
///   - 不加 .padding(4) — 系统 panel 自带 inset,再 pad 等于双重 padding。
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
        // NSPopover 时代这里要 .background(.regularMaterial) + 自定义圆角 +
        // stroke,因为 NSPopover 没有装饰。MenuBarExtra(.window) 是 SwiftUI scene,
        // 系统已经渲染 panel 背景 + 圆角 + 边框,这里只管内容布局。
        //
        // 如果以后想强制某种颜色,加 `.background(Color(nsColor: .windowBackgroundColor))`
        // 这类纯色;不要再叠 .regularMaterial —— 会跟系统材质打架变灰。
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
                Task { @MainActor in
                    NSApp.activate(ignoringOtherApps: true)
                    AppWindowFocus.focusMain()
                }
                // MenuBarExtra(.window) 在 focus 切到主窗口时自动 dismiss —
                // 不用手动管 popover 生命周期。
            }
            // 用 \.openSettings — 之前 NSApp.sendAction(showSettingsWindow:)
            // 从 MenuBarExtra 触发不稳定。
            MenuBarItem(label: "Settings…", shortcut: "⌘,") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                // MenuBarExtra 在 Settings 窗口浮现后自动 dismiss。
            }
            MenuBarItem(label: "Refresh SSH Config", shortcut: "⌘R") {
                // 之前 fire-and-forget Task — refresh() 抛异常被吞,~/.ssh/config
                // 出错用户看不到反馈就以为成功。接 do/catch 至少 print 到 stderr,
                // 后续 tunnelLogStore 暴露 public append 时可以替换为写日志。
                Task {
                    do {
                        try await container.sshHostManager.refresh()
                    } catch {
                        #if DEBUG
                        print("[JanusSSH] Refresh SSH Config failed: \(error)")
                        #endif
                    }
                }
                // 不主动关 popover — 用户想继续操作 menu bar 可以直接点,
                // 想看主窗口刷新的 hosts 手动点别处即可。MenuBarExtra 的
                // 自动 outside-click dismissal 跟之前 NSPopover 时代
                // dismissPopover() 行为等价。
            }
            rowDivider
            MenuBarItem(label: "Quit", shortcut: "⌘Q") {
                // MenuBarExtra 是 SwiftUI scene,App 退出时系统自动清理。
                // 直接 NSApp.terminate(nil) — 之前 NSPopover 时代需要先
                // dismiss popover + 拆 monitor 是为了防 .applicationDefined
                // 残留把 willTerminate 拖住,这套 hack 不再需要。
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
        // 切回 SwiftUI Button(action:) — NSPopover + .applicationDefined 时代
        // Button action 不 fire 是因为 .applicationDefined 面板首次 click 被
        // AppKit 抢做 key-window promotion。MenuBarExtra(.window) 的 panel
        // 同样有这个坑,但已经通过 MenuBarWindowAccessor 在 view 进 tree 时
        // 强制 makeKey 绕过 — Button 在 key panel 里能正常 fire,不需要再绕
        // 回 HStack + .onTapGesture。
        //
        // .buttonStyle(.plain) 移除系统默认的蓝色 focus ring / 按下高亮,
        // 由我们自己用 hoverHighlight + 不画 stroke 控制视觉。
        Button(action: performAction) {
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
        }
        .buttonStyle(.plain)
        // 设计稿:profile 行上下留 ~9pt 呼吸空间,不要挤
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        // StatusBadge 的 breathing halo 在缩放到最大时直径 ~14.4px,
        // 完全在 padding(横向 12 / 纵向 9)范围内。clipped() 作为兜底
        // — 万一未来 halo scale 调大,不会盖到 hover 框外。
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())  // 整行可点
        .hoverHighlight(hovering)
        // onHover 推到下一个 runloop tick — 鼠标若正好停在 row 上、popover
        // 一出现 .onHover 会立刻 fire,直接改 hovering 撞上 AppKit 的
        // window install-layout pass,触发 layoutSubtreeIfNeeded recursion warning。
        .onHover { h in
            Task { @MainActor in hovering = h }
        }
        .animation(.easeOut(duration: 0.08), value: hovering)
        // pending 状态(.starting/.reconnecting/.stopping)禁用整个 Button —
        // 之前用 .allowsHitTesting(!isPending) 是因为 .disabled 在 NSPopover
        // 上下文里会切掉 SwiftUI gesture 通道。MenuBarExtra + Button 路径
        // 下 .disabled 是安全的,用标准 API 取代手写 hit-test gate。
        .disabled(isPending)
        // Button 自动加 .isButton trait,VoiceOver 现在能正确读
        // "Production, button"。显式 .accessibilityLabel 仍需要 — Button
        // 默认读 HStack 第一个 Text(profile.name),已经是 profile 名,但
        // 显式声明让 a11y 行为对将来重构更鲁棒。
        .accessibilityLabel(Text(profile.name))
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
        // 切回 SwiftUI Button(action:) — NSPopover + .applicationDefined 时代
        // Button action 不 fire 是因为 .applicationDefined 面板首次 click 被
        // AppKit 抢做 key-window promotion。MenuBarExtra(.window) 同样有
        // 这个坑,但已经通过 MenuBarWindowAccessor 在 view 进 tree 时强制
        // makeKey 绕过 — Button 在 key panel 里能正常 fire。
        //
        // .buttonStyle(.plain) 去掉系统默认蓝色 focus ring / 按下高亮,
        // 由 hoverHighlight 自己控制视觉。
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
        }
        .buttonStyle(.plain)
        // 设计稿:menu item 上下 ~9pt 呼吸,与 profile 行保持节奏一致
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // hover 高亮作为 background — SwiftUI 的 .background
        // 会自动按 View 的实际尺寸渲染,而不是 label 的尺寸
        .hoverHighlight(hovering)
        .onHover { hovering = $0 }
        // Button 自动加 .isButton trait,VoiceOver 现在能读 "Open Application, button"。
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

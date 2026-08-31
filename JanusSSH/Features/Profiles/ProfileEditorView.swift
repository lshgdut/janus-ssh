import SwiftUI
import AppKit
import JanusSSHTunnelEngine

/// Profile 编辑/新建页 — 对齐 OpenDesign 原型
/// 布局:
///  ┌─────────────────────────────────────────────┐
///  │ [crumb]      Edit · Production   [N forwards · validated] │ ← 顶部条
///  │                                            [Cancel] [Save&Stop] [Save&Restart]│
///  ├──────────┬──────────────────────────────────┤
///  │ 1 基本信息 │ section1                         │
///  │ 2 Forwards│ section2                         │
///  │ 3 行为   │ section3                         │
///  │ 4 预览   │ section4                         │
///  ├──────────┴──────────────────────────────────┤
///  │ 路径说明                  [Delete] [Save]   │ ← 底部 sticky
///  └─────────────────────────────────────────────┘
struct ProfileEditorView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Profile
    @State private var issues: [ValidationIssue] = []
    @State private var currentStep: Int = 1
    /// save() 在跑时为 true — 用来:
    ///   1) 给 Save / Save & Stop / Save & Restart / Delete 按钮加 spinner
    ///      并 disable,避免重复点击触发并发 restart;
    ///   2) 关掉 .interactiveDismissDisabled,挡住 Cmd+W / 点关闭按钮;
    ///   3) 关掉内容区的 hit testing,防止用户改 draft 触发再次校验。
    @State private var isSaving: Bool = false
    /// restart() 抛错时填 localizedDescription,bind 到 .alert 显示。
    @State private var saveError: String?
    /// 区分新建/编辑 — 新建模式下隐藏 Delete Profile、Save&Stop、Save&Restart
    /// (这些操作只对已存在的 profile 才有意义)。
    let isNew: Bool

    init(initial: Profile, isNew: Bool = false) {
        _draft = State(initialValue: initial)
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                stepperSidebar
                    // 240 而非 200:让 "Port Forwards" 不再折行成两行。
                    // 之前 200 时 "Port Forwards" 折行是因为内边距 + 数字徽章 + 间距
                    // 把 label 压到 ~80pt,装不下 "Port Forwards" 整词。
                    .frame(width: 240)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    // 左侧 stepper 一起锁掉,避免用户边保存边点步骤切 section。
                    .allowsHitTesting(!isSaving)
                Divider()
                content
                    // 表单字段(textField / picker / stepper / row 增删)全部
                    // 关掉 hit testing,否则 save() 期间用户改了 draft 会触发
                    // 额外的 refresh() 校验,以及 onChange of draft 的状态抖动。
                    .allowsHitTesting(!isSaving)
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 1180, minHeight: 640)
        .onChange(of: draft) { _, _ in refresh() }
        .onAppear { refresh() }
        // save() 正在跑时禁止交互式关窗(Cmd+W / 红绿灯关闭按钮),
        // 否则刚发起 restart 就被用户关掉,后台 SSH 进程失去引用关系,
        // 复现"port in use"那类诡异状态。
        .interactiveDismissDisabled(isSaving)
        .alert(
            "Save failed",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // 左:面包屑
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles /")
                    .font(.caption).foregroundStyle(.secondary)
                // 标题跟着 isNew 走 — 之前用 draft.name.isEmpty 判,
                // 用户还没存盘就先在 name 里敲了字,标题就跳成 "Edit · xxx",
                // 暗示 profile 已存在,造成混淆。
                Text(isNew ? "New Profile" : "Edit · \(draft.name)")
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            // 中:状态 pill
            validationPill
            Spacer()
            // 右:动作按钮
            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.appSecondary)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                // Save&Stop / Save&Restart 只对已存在的 profile 有意义 —
                // 新建 profile 时 SSH tunnel 还没起,没东西可以 stop/restart。
                // 新建模式下底部 Save 按钮承担提交职责,Cmd+Return 走它。
                if !isNew {
                    Button {
                        save(restart: false)
                    } label: {
                        SaveActionLabel(
                            idle: "Save & Stop",
                            progress: "Stopping…",
                            isSaving: isSaving
                        )
                    }
                    .buttonStyle(.appSecondary)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(isSaving || !canSave)

                    Button {
                        save(restart: true)
                    } label: {
                        SaveActionLabel(
                            idle: "Save & Restart",
                            progress: "Restarting…",
                            isSaving: isSaving
                        )
                    }
                    .buttonStyle(.appPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSaving || !canSave)
                }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 14)
    }

    private var validationPill: some View {
        HStack(spacing: 6) {
            if hasErrors {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("\(draft.forwards.count) forwards · \(errorCount) errors")
                    .font(.caption).foregroundStyle(.red)
            } else if draft.forwards.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(draft.forwards.count) forwards · empty")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(draft.forwards.count) forwards · validated")
                    .font(.caption).foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((hasErrors ? Color.red : .green).opacity(0.1))
        )
    }

    // MARK: - Stepper sidebar

    private var stepperSidebar: some View {
        // 整体外侧 padding — 横 20 让 "基本信息" "Port Forwards" 不贴窗沿,
        // 竖 16 维持原有节奏。必须挂在 VStack 外,否则写在闭包里会触发
        // "Instance member 'padding' cannot be used on type 'View'" —
        // 因为 .padding 是 view 实例方法,不能脱离具体 view 单独写。
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps, id: \.number) { step in
                StepperItem(
                    number: step.number,
                    title: step.title,
                    isSelected: currentStep == step.number,
                    onTap: { withAnimation { currentStep = step.number } }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var steps: [(number: Int, title: String)] {
        [
            (1, "基本信息"),
            (2, "Port Forwards"),
            (3, "行为选项"),
            (4, "命令预览")
        ]
    }

    // MARK: - Content

    private var content: some View {
        // ScrollViewReader 让左侧 stepper sidebar 点击能滚动右侧内容到对应 section。
        // 每个 section 用 `.id(step.number)` 做锚点,onChange of currentStep 触发
        // scrollTo(anchor: .top) — 让 section 顶端对齐 viewport 顶端,而不是中间。
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    section1.id(1)
                    section2.id(2)
                    section3.id(3)
                    section4.id(4)
                }
                // 横向 56 / 纵向 32 — 第二轮放宽。40 仍然把 SSH HOST picker 挤到
                // 右窗沿;56 后表单左侧多出 ~16pt 呼吸空间,右侧也彻底留白。
                // 内部列宽不动 — 表格自然在左侧贴齐,右边留大空白,大气感出来。
                .padding(.horizontal, 56)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: currentStep) { _, newStep in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newStep, anchor: .top)
                }
            }
        }
    }

    // MARK: - Section 1: 基本信息

    private var section1: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(number: 1, title: "基本信息")
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROFILE NAME *")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("Production", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("SSH HOST *")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $draft.sshHostAlias) {
                        ForEach(container.sshHostManager.hosts) { h in
                            Text("\(h.alias) · \(h.user ?? "—")@\(h.hostname ?? "—")")
                                .tag(h.alias)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: - Section 2: Port Forwards

    private var section2: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(number: 2, title: "Port Forwards — 至少 1 条")
            Text("每条 Forward 对应一条 -L 参数。本地端口必须在 1-65535,远程主机不能为空。")
                .font(.caption).foregroundStyle(.secondary)

            // 表格头
            HStack(spacing: 12) {
                Text("LOCAL HOST")
                    .frame(width: 200, alignment: .leading)
                Text("LOCAL PORT")
                    .frame(width: 100, alignment: .leading)
                Text("REMOTE HOST")
                    .frame(width: 200, alignment: .leading)
                Text("REMOTE PORT")
                    .frame(width: 100, alignment: .leading)
                Text("LABEL")
                    .frame(width: 140, alignment: .leading)
                Spacer()
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)

            ForEach($draft.forwards) { $forward in
                ForwardRow(forward: $forward, allForwards: $draft.forwards)
            }

            Button {
                draft.forwards.append(PortForward(
                    localHost: "127.0.0.1", localPort: 0,
                    remoteHost: "127.0.0.1", remotePort: 0, label: nil))
            } label: {
                Label("Add Forward", systemImage: "plus")
            }
            .buttonStyle(.appSecondary)
            .controlSize(.small)

            // 错误汇总
            let portErrs = issues.filter { $0.severity == .error && $0.field?.contains("localPort") == true }
            if !portErrs.isEmpty {
                Text(portErrs.first?.message ?? "")
                    .font(.caption).foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Section 3: 行为

    private var section3: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(number: 3, title: "行为选项")

            BehaviorRow(
                title: "Enabled",
                description: "关闭后,该 Profile 不会出现在 Start All 列表中,且不会自动启动。",
                isOn: $draft.behavior.enabled
            )
            Divider()
            BehaviorRow(
                title: "Auto Reconnect",
                description: "SSH 进程异常退出时,自动按指数退避(1s/2s/5s/10s/30s)重连。用户主动 Stop 后禁止重连。",
                isOn: $draft.behavior.autoReconnect
            )
            Divider()
            BehaviorRow(
                title: "Auto Start on Launch",
                description: "应用启动时检测端口可用后自动启动该 Profile。",
                isOn: $draft.behavior.autoStart
            )
        }
    }

    // MARK: - Section 4: 命令预览

    private var section4: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(number: 4, title: "命令预览")
            Text("应用通过参数数组启动,不经过 shell")
                .font(.caption).foregroundStyle(.secondary)
            CommandPreview(profile: draft)
        }
    }

    // MARK: - Bottom bar (sticky footer)

    private var bottomBar: some View {
        HStack {
            // 左:路径说明
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("配置保存到 ~/Library/Application Support/com.lshgdut.janus-ssh/profiles.json。使用临时文件 + 原子 rename。")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            // 右:删除 + 保存
            // Delete 只对已存在的 profile 才有意义 — 新建 profile 还没存盘,
            // 没东西可删,留着只会误导用户。
            if !isNew {
                Button(role: .destructive) {
                    Task {
                        await container.deleteProfile(draft.id)
                        dismiss()
                    }
                } label: {
                    Label("Delete Profile", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.appSecondary)
                .tint(.red)
                .disabled(isSaving)
            }

            Button {
                save(restart: false)
            } label: {
                SaveActionLabel(
                    idle: "Save",
                    progress: "Saving…",
                    minWidth: 60,
                    isSaving: isSaving
                )
            }
            .buttonStyle(.appPrimary)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isSaving || !canSave)
        }
        .padding(.horizontal, 32).padding(.vertical, 14)
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !draft.name.isEmpty
            && issues.filter { $0.severity == .error }.isEmpty
    }

    private var hasErrors: Bool {
        !issues.filter { $0.severity == .error }.isEmpty
    }

    private var errorCount: Int {
        issues.filter { $0.severity == .error }.count
    }

    private func refresh() {
        let knownHosts = Set(container.sshHostManager.hosts.map { $0.alias })
        issues = container.validator.validate(draft, knownHosts: knownHosts)
    }

    private func save(restart: Bool) {
        // 同步守卫:SwiftUI 按钮被禁用了,但键盘快捷键在多事件并发时仍可能
        // 撞进来(例如长按 Cmd+Return 触发多次),这里再挡一次。
        guard !isSaving else { return }
        isSaving = true

        // @MainActor isolation:container / dismiss 都在主 actor 上,
        // Task { @MainActor in ... } 让所有 state 写入都在主线程,
        // 不会触发 SwiftUI 的 "Modifying state during view update" 警告。
        Task { @MainActor in
            defer { isSaving = false }
            do {
                await container.upsertProfile(draft)
                if restart {
                    // 之前用 try? 把错误吞了 — restart 失败(端口冲突 /
                    // 进程被外部杀 / 配置错等)用户看不到任何提示,直接
                    // dismiss 走人,回头只能去 profile 列表里看到 .error
                    // 状态,体验很突兀。现在让错误冒到 .alert 上。
                    try await container.tunnelManager.restart(profileID: draft.id)
                }
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}

// MARK: - Save action label
//
// 按钮 label 在 idle / progress 两种状态下用不同文案 + spinner。
// 单独抽出来是因为它同时挂在 Primary / Secondary 两种 button style 上。
//
// 进度态下 .controlSize(.small) 的 ProgressView 直径 16pt,
// 跟 32pt 高的按钮刚好居中,不会撑高 buttonRow。
//
// 注意:之前用过内部 @State isAnimating + .onAppear { isAnimating = true }
// 的写法,导致 SaveActionLabel 一进屏幕就永远停在 progress 态
// (isAnimating 永远不会变回 false),刚打开 editor 就看到所有保存
// 按钮挂着 spinner,用户以为在 loading。改成接收父视图传入的
// isSaving,label 状态完全由父视图驱动,不再有内部状态。
private struct SaveActionLabel: View {
    let idle: String
    let progress: String
    var minWidth: CGFloat? = nil
    let isSaving: Bool

    var body: some View {
        // 用 ZStack 叠两个 label 而不是 if/else 切换,
        // 这样按钮宽度取两者最大值,不会因文案变化发生"按钮宽度跳变"。
        ZStack {
            Text(idle)
                .opacity(isSaving ? 0 : 1)
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(progress)
            }
            .opacity(isSaving ? 1 : 0)
        }
        .frame(minWidth: minWidth)
        .animation(.easeInOut(duration: 0.15), value: isSaving)
    }
}

// MARK: - Side menu item

/// 编辑页左侧 stepper 的一行 — 抽出成独立 View 才能挂自己的 @State(hovering)。
/// 三个细节:
///   1. .contentShape(Rectangle()) 让整行都可点 — 不加的话只有文字区域响应,
///      空白 padding 区域点不到。
///   2. hover 时切手指光标 + 浅色背景 — 与 ButtonStyles 的处理方式一致。
///   3. onChange(of: hovering) 推/弹 NSCursor,与全 App 其它按钮同一套约定。
private struct StepperItem: View {
    let number: Int
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 20, alignment: .center)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundFill)
            .contentShape(Rectangle())   // 整行都是 hit area,不只是文字
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
    }

    /// 选中态 = accent tint(0.08),hover = 同一色调的 0.04,
    /// 普通态 = 透明。叠加在一起 hover + 选中视觉层级依然清楚。
    private var backgroundFill: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected
                  ? Color.accentColor.opacity(0.08)
                  : (hovering ? Color.accentColor.opacity(0.04) : .clear))
            .padding(.horizontal, 8)
            .onChange(of: hovering) { _, h in
                // 切手指光标 — 与 ButtonStyles.swift 的 push/pop 模式一致。
                // 嵌套 Button 用 .buttonStyle(.plain),SwiftUI 默认不会切光标,
                // 所以这里手动管 NSCursor 的 push/pop 栈。
                if h { NSCursor.pointingHand.push() }
                else  { NSCursor.pop() }
            }
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let number: Int
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(title)
                .font(.headline)
        }
    }
}

// MARK: - Behavior row

private struct BehaviorRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Forward row (single line of the table)

private struct ForwardRow: View {
    @Binding var forward: PortForward
    @Binding var allForwards: [PortForward]

    var body: some View {
        HStack(spacing: 12) {
            // LOCAL HOST
            TextField("127.0.0.1", text: $forward.localHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 200)
            // LOCALPORT — 右对齐数字
            TextField("15432", value: $forward.localPort, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .font(.system(.body, design: .monospaced))
                .frame(width: 100)
            // 箭头
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .font(.callout)
            // REMOTEHOST
            TextField("127.0.0.1", text: $forward.remoteHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 200)
            // REMOTEPORT
            TextField("5432", value: $forward.remotePort, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .font(.system(.body, design: .monospaced))
                .frame(width: 100)
            // LABEL — 可选,例如 envoy-admin / pg / etcd。
            // 用 monospaced + 圆角边框跟端口字段视觉对齐;
            // 不限 1 行也不报错 — 留空就是未标注,ProfileListView 会跳过。
            TextField("envoy-admin", text: Binding<String>(
                get: { forward.label ?? "" },
                set: { newValue in forward.label = newValue.isEmpty ? nil : newValue }
            ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 140)
            // Delete — 每条 forward 只留这一个 row 动作;
            // 复制整个 ssh 命令走底部 CommandPreview 的 Copy 按钮,
            // 单条 -L 参数复制用处不大(用户要复制也都是复制完整命令)。
            Button(role: .destructive) {
                allForwards.removeAll { $0.id == forward.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(allForwards.count <= 1)
            .help("删除此 Forward")
        }
    }
}

// MARK: - Command preview (terminal style with Copy)

private struct CommandPreview: View {
    let profile: Profile
    @State private var cmd: String = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 之前:硬编码 .black / .white,light 模式下变成突兀的黑色块;
        // 现在跟 colorScheme 走 — light 灰底深字,dark 深底浅字。
        // 布局也简化:不再分 header bar + body 两段,Copy 按钮浮在右上角,
        // 命令区右侧预留 76pt 给按钮,不重叠。
        ZStack(alignment: .topTrailing) {
            // 命令文本(横向滚动)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(cmd.isEmpty ? "$ ssh production" : cmd)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(codeForeground)
                    .padding(14)
                    .padding(.trailing, 76)   // 给右上角的 Copy 按钮留位置
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Copy 按钮 — 浮在右上角,去掉原来 .tint(.white) 强制白色
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(cmd, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.appSecondary)
            .controlSize(.small)
            .padding(8)
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(codeBorder, lineWidth: 1)
        )
        .onAppear { rebuild() }
        .onChange(of: profile) { _, _ in rebuild() }
    }

    /// Code block 背景 — 比页面背景深一档(light)/浅一档(dark),让 code block
    /// 视觉上是"内嵌"的。完全用灰度,避免在两个 mode 间切色相。
    private var codeBackground: Color {
        colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.96)
    }

    /// 文字 — 高对比度但不刺眼:light mode 用 #2E2E2E(几乎黑但略带暖),
    /// dark mode 用 #E6E6E6(几乎白但略带冷)。比纯黑/纯白柔和。
    private var codeForeground: Color {
        colorScheme == .dark ? Color(white: 0.90) : Color(white: 0.18)
    }

    /// 边框 — 极淡,只是为了跟页面 bg 分开,不喧宾夺主
    private var codeBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private func rebuild() {
        do {
            let snapshot = ProfileSnapshot(profile)
            let built = try SSHCommandBuilder().build(profile: snapshot)
            cmd = "$ " + ([built.executable.path] + built.arguments).joined(separator: " \\\n  ")
        } catch {
            cmd = "$ ssh \(profile.sshHostAlias.isEmpty ? "<host>" : profile.sshHostAlias)   # 至少需要 1 条 Forward"
        }
    }
}
// MARK: - ProfileEditorWindow
//
// 独立 window 场景 — 监听 AppContainer.editingProfile
// 非 nil 时显示编辑器,nil 时显示空白(等用户操作)
// 避免 .sheet 在 macOS 上的固定尺寸截断长内容

import AppKit

struct ProfileEditorWindow: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        Group {
            if let profile = container.editingProfile {
                ProfileEditorView(initial: profile, isNew: container.editingProfileIsNew)
                    .onDisappear { container.closeEditor() }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No profile selected")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

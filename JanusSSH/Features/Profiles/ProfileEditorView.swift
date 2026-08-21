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

    init(initial: Profile) {
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                stepperSidebar
                    .frame(width: 200)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                Divider()
                content
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 880, minHeight: 640)
        .onChange(of: draft) { _, _ in refresh() }
        .onAppear { refresh() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // 左:面包屑
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles /")
                    .font(.caption).foregroundStyle(.secondary)
                Text(draft.name.isEmpty ? "New Profile" : "Edit · \(draft.name)")
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            // 中:状态 pill
            validationPill
            Spacer()
            // 右:动作按钮
            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Save & Stop") { save(restart: false) }
                    .buttonStyle(.bordered)
                    .disabled(!canSave)
                Button("Save & Restart") { save(restart: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSave)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps, id: \.number) { step in
                Button {
                    withAnimation { currentStep = step.number }
                } label: {
                    HStack(spacing: 12) {
                        Text("\(step.number)")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(currentStep == step.number ? Color.accentColor : .secondary)
                            .frame(width: 20, alignment: .center)
                        Text(step.title)
                            .font(.callout)
                            .foregroundStyle(currentStep == step.number ? .primary : .secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(
                        currentStep == step.number
                            ? Color.accentColor.opacity(0.08)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                section1
                section2
                section3
                section4
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
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
                    remoteHost: "", remotePort: 0, label: nil))
            } label: {
                Label("Add Forward", systemImage: "plus")
            }
            .buttonStyle(.bordered)
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
            Button(role: .destructive) {
                Task {
                    await container.deleteProfile(draft.id)
                    dismiss()
                }
            } label: {
                Label("Delete Profile", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button {
                save(restart: false)
            } label: {
                Text("Save").frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSave)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
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
        Task {
            await container.upsertProfile(draft)
            if restart {
                try? await container.tunnelManager.restart(profileID: draft.id)
            }
            dismiss()
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
            TextField("15432", value: $forward.localPort, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .font(.system(.body, design: .monospaced))
                .frame(width: 100)
            // 箭头
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .font(.callout)
            // REMOTEHOST
            TextField("10.20.0.15", text: $forward.remoteHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 200)
            // REMOTEPORT
            TextField("5432", value: $forward.remotePort, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .font(.system(.body, design: .monospaced))
                .frame(width: 100)
            // Copy
            Button {
                let port = NSPasteboard.general
                port.clearContents()
                port.setString(forward.sshArgument, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制 -L 参数")
            // Delete
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Copy 按钮
            HStack {
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(cmd, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85))

            // 命令文本
            ScrollView(.horizontal, showsIndicators: false) {
                Text(cmd.isEmpty ? "$ ssh production" : cmd)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 1))
        .onAppear { rebuild() }
        .onChange(of: profile) { _, _ in rebuild() }
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
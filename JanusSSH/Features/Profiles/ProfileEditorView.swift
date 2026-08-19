import SwiftUI
import JanusSSHTunnelEngine

struct ProfileEditorView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Profile
    @State private var issues: [ValidationIssue] = []

    init(initial: Profile) {
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section1_basic
                    section2_forwards
                    section3_behavior
                    section4_commandPreview
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 600)
        .onChange(of: draft) { _, _ in refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles /").font(.caption).foregroundStyle(.secondary)
                Text(draft.name.isEmpty ? "New Profile" : draft.name)
                    .font(.title2).fontWeight(.medium)
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Button("Save & Stop") { save(restart: false) }.buttonStyle(.bordered)
                    .disabled(!issues.filter { $0.severity == .error }.isEmpty || draft.name.isEmpty)
                Button("Save & Restart") { save(restart: true) }.buttonStyle(.borderedProminent)
                    .disabled(!issues.filter { $0.severity == .error }.isEmpty || draft.name.isEmpty)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var section1_basic: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("1 基本信息", systemImage: "1.circle").font(.headline)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile Name *").font(.caption).foregroundStyle(.secondary)
                    TextField("Production", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH Host *").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $draft.sshHostAlias) {
                        ForEach(container.sshHostManager.hosts) { h in
                            Text("\(h.alias) · \(h.user ?? "?")@\(h.hostname ?? "?")")
                                .tag(h.alias)
                        }
                    }.labelsHidden()
                }
            }
        }
    }

    private var section2_forwards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("2 Port Forwards — 至少 1 条", systemImage: "2.circle").font(.headline)
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

            // 错误汇总
            let errs = issues.filter { $0.severity == .error && $0.field?.contains("localPort") == true }
            if !errs.isEmpty {
                Text(errs.first?.message ?? "")
                    .font(.caption).foregroundStyle(.red)
                    .padding(8).background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var section3_behavior: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("3 行为选项", systemImage: "3.circle").font(.headline)
            Toggle("Enabled", isOn: $draft.behavior.enabled)
            Toggle("Auto Reconnect (指数退避 1/2/5/10/30s)", isOn: $draft.behavior.autoReconnect)
            Toggle("Auto Start on Launch", isOn: $draft.behavior.autoStart)
        }
    }

    private var section4_commandPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("4 命令预览", systemImage: "4.circle").font(.headline)
            Text("应用通过参数数组启动,不经过 shell")
                .font(.caption).foregroundStyle(.secondary)
            CommandPreview(profile: draft)
        }
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                Task {
                    await container.deleteProfile(draft.id)
                    dismiss()
                }
            } label: {
                Label("Delete Profile", systemImage: "trash")
            }.buttonStyle(.bordered)

            Spacer()
            Text("保存到 ~/Library/Application Support/com.lshgdut.janus-ssh/profiles.json")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
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

private struct ForwardRow: View {
    @Binding var forward: PortForward
    @Binding var allForwards: [PortForward]

    var body: some View {
        HStack(spacing: 8) {
            TextField("127.0.0.1", text: $forward.localHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            TextField("15432", value: $forward.localPort, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .font(.system(.body, design: .monospaced))
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            TextField("db.internal", text: $forward.remoteHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            TextField("5432", value: $forward.remotePort, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .font(.system(.body, design: .monospaced))
            TextField("label", text: Binding(
                get: { forward.label ?? "" },
                set: { forward.label = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            Button(role: .destructive) {
                allForwards.removeAll { $0.id == forward.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(allForwards.count <= 1)
        }
    }
}

private struct CommandPreview: View {
    let profile: Profile
    @State private var cmd: String = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(cmd)
                .font(.system(.caption, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.black, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(.white)
        .onAppear { rebuild() }
        .onChange(of: profile) { _, _ in rebuild() }
    }

    private func rebuild() {
        do {
            let snapshot = ProfileSnapshot(profile)
            let built = try SSHCommandBuilder().build(profile: snapshot)
            cmd = ([built.executable.path] + built.arguments).joined(separator: " \\\n  ")
        } catch {
            cmd = "(no forwards)"
        }
    }
}
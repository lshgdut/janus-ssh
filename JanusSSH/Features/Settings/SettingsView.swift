import SwiftUI
import ServiceManagement
import JanusSSHTunnelEngine

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    SettingsGroup(title: "通用", description: "应用启动行为与全局开关") {
                        ToggleRow(title: "Launch at Login",
                                  description: "登录 macOS 时自动启动 janus-ssh",
                                  isOn: settings.general.launchAtLogin,
                                  onChange: { v in
                                      Task { await container.settingsManager.update { $0.general.launchAtLogin = v } }
                                      if v { registerLoginItem() } else { unregisterLoginItem() }
                                  })
                        ToggleRow(title: "Show Menu Bar Icon",
                                  description: "在 macOS Menu Bar 显示应用图标",
                                  isOn: settings.general.showMenuBarIcon,
                                  onChange: { v in
                                      Task { await container.settingsManager.update { $0.general.showMenuBarIcon = v } }
                                  })
                        ToggleRow(title: "Quit on Window Close",
                                  description: "关闭窗口时退出应用,所有 SSH Tunnel 一并停止",
                                  isOn: settings.general.quitOnWindowClose,
                                  onChange: { v in
                                      Task { await container.settingsManager.update { $0.general.quitOnWindowClose = v } }
                                  })
                    }

                    SettingsGroup(title: "SSH 配置", description: "应用读取的 SSH Config 路径与解析选项") {
                        PathRow(title: "SSH Config Path",
                                description: "默认 ~/.ssh/config",
                                value: settings.ssh.configPath)
                        ToggleRow(title: "Include",
                                  description: "解析 Include 指令中引用的文件",
                                  isOn: settings.ssh.resolveIncludes,
                                  onChange: { v in
                                      Task { await container.settingsManager.update { $0.ssh.resolveIncludes = v } }
                                  })
                        ActionRow(title: "Refresh on Demand",
                                   description: "点击后立即重新解析 SSH Config",
                                   actionLabel: "Refresh Now",
                                   action: { Task { await container.sshHostManager.refresh() } })
                    }

                    SettingsGroup(title: "Tunnels", description: "Tunnel 进程管理") {
                        ToggleRow(title: "Auto Reconnect",
                                  description: "默认对所有新 Profile 启用。指数退避:1s/2s/5s/10s/30s",
                                  isOn: settings.tunnel.defaultAutoReconnect,
                                  onChange: { v in
                                      Task { await container.settingsManager.update { $0.tunnel.defaultAutoReconnect = v } }
                                  })
                        ToggleRow(title: "ExitOnForwardFailure",
                                  description: "任一 Forward 失败时让 SSH 退出",
                                  isOn: settings.tunnel.exitOnForwardFailure,
                                  onChange: { v in
                                      Task { await container.settingsManager.update { $0.tunnel.exitOnForwardFailure = v } }
                                  })
                    }

                    SettingsGroup(title: "存储与备份", description: "Profile 数据的存储与备份策略") {
                        PathRow(title: "Profiles File",
                                description: "使用临时文件 + fsync + 原子 rename",
                                value: "~/Library/Application Support/com.lshgdut.janus-ssh/profiles.json")
                        ActionRow(title: "Backups",
                                  description: "最近 10 次自动备份,损坏时可通过 Restore 恢复",
                                  actionLabel: "View All Backups", action: { })
                        ActionRow(title: "Export / Import",
                                  description: "导出所有 Profile 为可分享的 JSON 文件(不含 SSH 凭据)",
                                  actionLabel: "Export / Import", action: { })
                    }

                    DangerZoneGroup(container: container)
                }
                .padding(20)
            }
        }
    }

    private var settings: AppSettings { container.settingsManager.state }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings").font(.title2).fontWeight(.medium)
                Text("所有改动自动保存到 ~/Library/Application Support/com.lshgdut.janus-ssh/")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SavedIndicator()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.background)
    }

    private func registerLoginItem() {
        try? SMAppService.mainApp.register()
    }
    private func unregisterLoginItem() {
        try? SMAppService.mainApp.unregister()
    }
}

private struct SavedIndicator: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text("All changes saved").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.background, in: Capsule())
        .overlay(Capsule().stroke(.separator))
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
            VStack(spacing: 0) { content }.padding(.vertical, 8)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }
}

private struct ToggleRow: View {
    let title: String
    let description: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct PathRow: View {
    let title: String
    let description: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Button("Browse…") {}.buttonStyle(.bordered)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct ActionRow: View {
    let title: String
    let description: String
    let actionLabel: String
    let action: () -> Void
    var tint: Color = .accentColor

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionLabel, action: action)
                .buttonStyle(.bordered)
                .tint(tint)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct DangerZoneGroup: View {
    let container: AppContainer
    @State private var showResetConfirm = false

    var body: some View {
        // ZStack 显式把背景放到所有内容之下,避免按钮自带的白色覆盖 VStack 背景
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.08))

            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("!").font(.caption).bold()
                            .foregroundStyle(.white).frame(width: 16, height: 16)
                            .background(.red, in: Circle())
                        Text("危险操作").font(.headline).foregroundStyle(.red)
                    }
                    Text("这些操作不可恢复,请谨慎").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().background(.red.opacity(0.3))

                ActionRow(title: "Stop All Tunnels",
                          description: "停止所有由本应用管理的 SSH Tunnel,然后关闭所有 SSH 进程",
                          actionLabel: "Stop All",
                          action: { Task { await container.tunnelManager.stopAll() } },
                          tint: .red)

                Divider().background(.red.opacity(0.3))

                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset Profiles").font(.body)
                            Text("删除全部 Profile 与本地状态,不可恢复").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Reset…").font(.caption)
                    }
                }
                .buttonStyle(.bordered).tint(.red)
                .padding(.horizontal, 20).padding(.vertical, 10)

                if showResetConfirm {
                    Divider().background(.red.opacity(0.3))
                    HStack {
                        Text("输入 RESET 确认:").font(.caption)
                        TextField("RESET", text: .constant(""))
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                        Button("Confirm") {
                            for p in container.profiles {
                                Task { await container.deleteProfile(p.id) }
                            }
                            showResetConfirm = false
                        }.buttonStyle(.borderedProminent).tint(.red)
                    }
                    .padding(20)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.red.opacity(0.5)))
    }
}
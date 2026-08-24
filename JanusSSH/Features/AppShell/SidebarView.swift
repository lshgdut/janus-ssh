import SwiftUI

struct SidebarView: View {
    @Environment(AppContainer.self) private var container
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("导航")
            VStack(spacing: 0) {
                SidebarRow(item: .profiles, systemImage: "square.grid.2x2", title: "Profiles", selection: $selection)
                SidebarRow(item: .sshHosts, systemImage: "network", title: "SSH Hosts", selection: $selection)
                SidebarRow(item: .settings, systemImage: "gear", title: "Settings", selection: $selection)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        // 整体配色与 .sidebar style 一致
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
    }
}

/// 自定义 sidebar 行 — 直接用 VStack 而不是 List,
/// 因为 macOS 上 List 的 .sidebar style 行间距 / hit-test 都不可控。
/// VStack + Button + onHover 实现完全无缝、整行可点、严丝合缝的高亮。
private struct SidebarRow: View {
    let item: SidebarItem
    let systemImage: String
    let title: String
    @Binding var selection: SidebarItem?
    @State private var hovering = false

    private var isSelected: Bool { selection == item }

    var body: some View {
        Button(action: { selection = item }) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(highlightBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 外层 contentShape + 让 onHover 跟 Button 整体走
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(hovering ? 0.30 : 0.18))
                // 左右各缩 6pt,与 .sidebar style 默认 inset 对齐,
                // 上下来填满整行,严丝合缝
                .padding(.horizontal, 6)
        } else if hovering {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.15))
                .padding(.horizontal, 6)
        }
        // 非选中 + 未 hover:不渲染任何背景
    }
}
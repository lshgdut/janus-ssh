import SwiftUI
import JanusSSHTunnelEngine

struct TunnelLogView: View {
    @Environment(AppContainer.self) private var container
    let profileID: UUID

    @State private var entries: [TunnelLogStore.Entry] = []
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable {
        case all = "All", app = "App", stdout = "stdout", stderr = "stderr"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            Divider()
            logContent
        }
        .background(.black)
        .task { await subscribe() }
    }

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredEntries) { entry in
                        LogLineView(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: entries) { _, _ in
                if let last = filteredEntries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Logs").font(.caption).fontWeight(.medium).textCase(.uppercase)
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 8) {
                Button("Auto-scroll") { }.buttonStyle(.borderless).foregroundStyle(.white)
                Button("Clear") {
                    Task { await container.logStore.clear(profileID: profileID); entries = [] }
                }.buttonStyle(.borderless).foregroundStyle(.white)
            }
        }
        .padding(12)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Filter.allCases, id: \.self) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.rawValue).font(.caption).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .background(filter == f ? Color.white.opacity(0.1) : Color.clear)
                .overlay(alignment: .bottom) {
                    if filter == f {
                        Rectangle().fill(Color.accentColor).frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var body2: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredEntries) { entry in
                        LogLineView(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: entries) { _, _ in
                if let last = filteredEntries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var filteredEntries: [TunnelLogStore.Entry] {
        switch filter {
        case .all: return entries
        case .app: return entries.filter { $0.kind == .app }
        case .stdout: return entries.filter { $0.kind == .stdout }
        case .stderr: return entries.filter { $0.kind == .stderr }
        }
    }

    private func subscribe() async {
        let s = await container.logStore.subscribe(profileID: profileID)
        // 先填初始 buffer
        let initial = await container.logStore.snapshot(profileID: profileID)
        entries = initial
        for await entry in s {
            entries.append(entry)
            if entries.count > 1000 {
                entries.removeFirst(entries.count - 1000)
            }
        }
    }
}

private struct LogLineView: View {
    let entry: TunnelLogStore.Entry
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString(entry.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.gray).frame(width: 70, alignment: .leading)
            Text(entry.kind.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.blue).frame(width: 50, alignment: .leading)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(textColor)
        }
    }
    private var textColor: Color {
        switch entry.level {
        case .error: return .red.opacity(0.9)
        case .warn: return .orange
        case .info: return .white
        }
    }
    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
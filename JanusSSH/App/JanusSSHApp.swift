import SwiftUI
import JanusSSHTunnelEngine

@main
struct JanusSSHApp: App {
    @State private var container: AppContainer

    init() {
        let container = AppContainer.bootstrap()
        _container = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup("Janus SSH", id: "main") {
            RootView()
                .environment(container)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Profile") {
                    NotificationCenter.default.post(name: .newProfileRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(container)
        } label: {
            // Template NSImage — macOS 自动反色适配 light/dark menu bar
            Image(nsImage: makeMenuBarIcon())
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(container)
                .frame(minWidth: 720, minHeight: 560)
        }
    }
}

extension Notification.Name {
    static let newProfileRequested = Notification.Name("janus.newProfileRequested")
}

extension JanusSSHApp {
    /// 构造 menu bar 图标 — SF Symbol 转成 template NSImage
    /// macOS 看到 .alwaysTemplate 会自动反色适配 light/dark menu bar
    fileprivate func makeMenuBarIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                            accessibilityDescription: "Janus SSH")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
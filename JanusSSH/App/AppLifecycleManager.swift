import Foundation
import AppKit
import Observation
import JanusSSHTunnelEngine

/// App 生命周期管理 — 处理 Quit / Shutdown / Wake 事件
@MainActor
@Observable
final class AppLifecycleManager {
    private let tunnelManager: TunnelManager
    private let reconnectController: ReconnectController
    private let settingsManager: SettingsManager

    private var observers: [NSObjectProtocol] = []

    init(
        tunnelManager: TunnelManager,
        reconnectController: ReconnectController,
        settingsManager: SettingsManager
    ) {
        self.tunnelManager = tunnelManager
        self.reconnectController = reconnectController
        self.settingsManager = settingsManager
    }

    func start() {
        // Quit
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleQuit()
            }
        })

        // macOS 关机 / 注销
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handlePowerOff()
            }
        })
    }

    private func handleQuit() async {
        reconnectController.cancelAll()
        await tunnelManager.stopAll()
    }

    private func handlePowerOff() async {
        reconnectController.cancelAll()
        await tunnelManager.stopAll()
    }

    deinit {
        for o in observers {
            NotificationCenter.default.removeObserver(o)
        }
    }
}
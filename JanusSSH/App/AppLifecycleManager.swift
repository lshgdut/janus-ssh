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

    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

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
        // Quit — willTerminate 是同步通知,App 退出前最后一刻。
        // 必须同步触发 SIGKILL,不能走 Task(异步任务来不及完成,SSH 就成孤儿了)。
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [tunnelManager, reconnectController] _ in
            // 异步但 fire-and-forget:reconnectController 是 actor,无法同步访问
            Task { await reconnectController.cancelAll() }
            // 同步:SIGKILL 整个 SSH 进程组,不等待
            tunnelManager.stopAllNow()
        })

        // macOS 关机 / 注销 — 同样要走同步 SIGKILL
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil, queue: .main
        ) { [tunnelManager, reconnectController] _ in
            Task { await reconnectController.cancelAll() }
            tunnelManager.stopAllNow()
        })
    }

    deinit {
        let observersCopy = observers
        Task { @MainActor in
            for o in observersCopy {
                NotificationCenter.default.removeObserver(o)
            }
        }
    }
}
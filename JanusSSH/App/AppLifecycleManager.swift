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
    /// 防重入标志 — start()/stop() 必须在 MainActor 上串行调用,但 stop()
    /// 也可能在 deinit 的兜底路径里跑到,需要确保 NotificationCenter.removeObserver
    /// 不会被同一个 token 调两次(虽然 NotificationCenter 本身幂等,但避免无意义工作)。
    nonisolated(unsafe) private var stopped = false

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
        //
        // 之前写 queue: .main — closure 被 schedule 到主 run loop,异步执行。
        // NSApp.terminate() post 完通知后就走,AppKit 不得不 drain run loop 来
        // 派发这个 closure,然后才能 exit,所以"点了 Quit 好一会才退"。
        // 改成 nil — closure 在 post 线程(main)上同步执行,AppKit 紧接着就 exit,
        // 实测立刻退。同时 tunnelManager.stopAllNow() 自身是 @MainActor + sync,
        // 从 main  thread 调用没 isolation 问题。
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: nil
        ) { [tunnelManager, reconnectController] _ in
            // 异步但 fire-and-forget:reconnectController 是 actor,无法同步访问
            Task { await reconnectController.cancelAll() }
            // 同步:SIGKILL 整个 SSH 进程组,不等待
            tunnelManager.stopAllNow()
        })

        // macOS 关机 / 注销 — 同样要走同步 SIGKILL
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil, queue: nil
        ) { [tunnelManager, reconnectController] _ in
            Task { await reconnectController.cancelAll() }
            tunnelManager.stopAllNow()
        })
    }

    /// 同步、显式释放 NotificationCenter 观察者 + 释放 tunnelManager /
    /// reconnectController 强引用。
    ///
    /// 之前只在 deinit 里 fire-and-forget Task { @MainActor in removeObserver }
    /// ——App 退出时 deinit 跟 process termination 赛跑,Task 不一定来得及跑,
    /// 观察者会一直钉在 NotificationCenter 上,闭包里强引用的 tunnelManager /
    /// reconnectController 也跟着泄漏到进程结束。显式 stop() 让上层能在 App
    /// willTerminate / 测试 teardown 时同步清理。
    ///
    /// NotificationCenter.removeObserver 对同一 token 多次调用安全,所以
    /// stop() + deinit 兜底路径并存没问题。
    func stop() {
        guard !stopped else { return }
        stopped = true
        let toRemove = observers
        observers.removeAll()
        for o in toRemove {
            NotificationCenter.default.removeObserver(o)
        }
    }

    deinit {
        // 兜底:如果调用方忘了 stop() / stop() 没跑到(异常退出),
        // 仍然尝试清理。stopped 防重入,避免跟 stop() 抢同一批 token。
        guard !stopped else { return }
        stopped = true
        let observersCopy = observers
        observers.removeAll()
        // deinit 在 @MainActor 类上是 nonisolated 上下文,NotificationCenter
        // 本身是 thread-safe,这里直接同步调用即可,不必再走 Task。
        for o in observersCopy {
            NotificationCenter.default.removeObserver(o)
        }
    }
}
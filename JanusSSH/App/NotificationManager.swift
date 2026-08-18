import Foundation
import UserNotifications
import JanusSSHTunnelEngine

/// 通知管理 — Tunnel Failed / Reconnected 事件通过系统通知展示
@MainActor
final class NotificationManager {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifyTunnelFailed(profileName: String, error: String) async {
        await post(title: "Tunnel Failed: \(profileName)", body: error)
    }

    func notifyTunnelReconnected(profileName: String) async {
        await post(title: "Tunnel Reconnected: \(profileName)", body: "Auto-reconnect succeeded")
    }

    private func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(req)
    }
}
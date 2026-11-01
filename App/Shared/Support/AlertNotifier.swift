import Foundation
import UserNotifications
import StarlinkKit

/// Turns a `TriggeredAlert` from StarlinkKit's `AutomationEngine` into a local system notification.
/// Local only — no push server, no account; the alert never leaves the device.
enum AlertNotifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ alert: TriggeredAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

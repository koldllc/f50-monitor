import Foundation
import UserNotifications

final class SMSNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var lastUnreadCount: Int?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func updateUnreadCount(_ unreadCount: Int) {
        defer { lastUnreadCount = unreadCount }
        guard let previousCount = lastUnreadCount,
              unreadCount > previousCount else { return }

        let newMessageCount = unreadCount - previousCount
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "F50 收到新短信"
            content.body = newMessageCount == 1
                ? "有 1 条新短信，点击菜单栏查看。"
                : "有 \(newMessageCount) 条新短信，点击菜单栏查看。"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "f50-sms-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

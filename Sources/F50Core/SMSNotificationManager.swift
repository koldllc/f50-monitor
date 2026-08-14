import Foundation
import UserNotifications

public final class SMSNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var lastUnreadCount: Int?
    private var hasRequestedAuthorization = false

    public override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// 在启动时请求一次通知授权，避免每次新短信都重复请求
    public func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func updateUnreadCount(_ unreadCount: Int) {
        defer { lastUnreadCount = unreadCount }
        guard let previousCount = lastUnreadCount,
              unreadCount > previousCount else { return }

        let newMessageCount = unreadCount - previousCount
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
        UNUserNotificationCenter.current().add(request)
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

import SwiftUI
import F50Core
import BackgroundTasks

/// 应用委托：注册后台刷新任务，处理新短信本地通知
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let backgroundTaskID = "com.f50.monitor.ios.refresh"

    let smsNotificationManager = SMSNotificationManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = smsNotificationManager
        smsNotificationManager.requestAuthorizationIfNeeded()

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskID,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        return true
    }

    /// 提交下一次后台刷新（系统按需调度，不保证频率）
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let smsManager = smsNotificationManager

        Task { @MainActor in
            // 临时 fetcher：init 即触发一次设备取数
            let fetcher = F50Fetcher()
            // 等待取数完成（最多 20 秒）
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !fetcher.isFetching { break }
            }
            // 新短信提醒（仅当未读数增加时触发本地通知）
            if fetcher.status.isOnline {
                smsManager.updateUnreadCount(fetcher.status.smsUnreadCount)
            }
            task.setTaskCompleted(success: true)
        }

        // 系统到期兜底
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }
}

@main
struct F50iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var fetcher = F50Fetcher()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(fetcher: fetcher)
                .onAppear {
                    appDelegate.smsNotificationManager.requestAuthorizationIfNeeded()
                }
                .onReceive(fetcher.$status) { status in
                    guard status.isOnline else { return }
                    appDelegate.smsNotificationManager.updateUnreadCount(status.smsUnreadCount)
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        appDelegate.scheduleBackgroundRefresh()
                    }
                }
        }
    }
}

struct ContentView: View {
    @ObservedObject var fetcher: F50Fetcher

    var body: some View {
        TabView {
            StatusView(fetcher: fetcher)
                .tabItem { Label("状态", systemImage: "antenna.radiowaves.left.and.right") }
            SMSView(fetcher: fetcher)
                .tabItem { Label("短信", systemImage: "envelope.fill") }
                .badge(fetcher.status.smsUnreadCount > 0 ? fetcher.status.smsUnreadCount : 0)
            SettingsView(fetcher: fetcher)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}

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

        let refreshTask = Task { @MainActor in
            let fetcher = F50Fetcher()
            await fetcher.fetchDataAsync()

            if fetcher.status.isOnline {
                F50WidgetDataStore.saveStatus(fetcher.status)
                smsManager.updateUnreadCount(fetcher.status.smsUnreadCount)
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshTask.cancel()
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
                    // 同步给小组件（App Group 共享存储）
                    F50WidgetDataStore.saveStatus(status)
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
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            StatusView(fetcher: fetcher)
                .tabItem {
                    Label("状态", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(0)

            SMSView(fetcher: fetcher)
                .tabItem {
                    Label("短信", systemImage: "envelope.fill")
                }
                .badge(fetcher.status.smsUnreadCount > 0 ? fetcher.status.smsUnreadCount : 0)
                .tag(1)

            SettingsView(fetcher: fetcher)
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(Color.blue)
    }
}

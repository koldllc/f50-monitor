import SwiftUI
import F50Core

@main
struct F50iOSApp: App {
    @StateObject private var fetcher = F50Fetcher()
    private let smsNotificationManager = SMSNotificationManager()

    init() {
        // 设置通知代理（前台横幅展示）
        UNUserNotificationCenter.current().delegate = smsNotificationManager
    }

    var body: some Scene {
        WindowGroup {
            ContentView(fetcher: fetcher)
                .onAppear {
                    smsNotificationManager.requestAuthorizationIfNeeded()
                }
                .onReceive(fetcher.$status) { status in
                    guard status.isOnline else { return }
                    smsNotificationManager.updateUnreadCount(status.smsUnreadCount)
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

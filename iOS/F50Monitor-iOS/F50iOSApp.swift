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
    @State private var isShowingInitialSetup: Bool

    init() {
        _isShowingInitialSetup = State(initialValue: F50Configuration.needsInitialSetup)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(fetcher: fetcher)
                .fullScreenCover(isPresented: $isShowingInitialSetup) {
                    InitialSetupView(fetcher: fetcher) {
                        isShowingInitialSetup = false
                    }
                    .interactiveDismissDisabled()
                }
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

private struct InitialSetupView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onComplete: () -> Void

    @State private var address = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isDiscovering = true
    @State private var discoveryMessage = "正在查找局域网中的 F50…"

    private var isAddressValid: Bool {
        F50Configuration.isValidAddress(address)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("欢迎使用 F50 Monitor")
                        .font(.title2.bold())
                    Text("请输入 F50 的地址和后台密码，之后可随时在设置中修改。")
                        .foregroundColor(.secondary)
                }

                Section {
                    TextField("设备地址，例如 192.168.0.1", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    HStack(spacing: 6) {
                        if isDiscovering {
                            ProgressView()
                        }
                        Text(discoveryMessage)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if !address.isEmpty && !isAddressValid {
                        Text("请输入正确的 IP 地址或域名")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    HStack {
                        Group {
                            if isPasswordVisible {
                                TextField("后台密码", text: $password)
                            } else {
                                SecureField("后台密码", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("连接设备")
                } footer: {
                    Text("UFI 后台口令为可选项，可稍后在设置中单独填写。")
                }
            }
            .navigationTitle("初始设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始使用") {
                        fetcher.applyConfiguration(
                            baseURL: F50Configuration.normalizeBaseURL(address),
                            password: password,
                            ufiToken: "",
                            refreshInterval: fetcher.refreshInterval,
                            displayMode: fetcher.displayMode
                        )
                        UserDefaults.standard.set(true, forKey: F50Configuration.initialSetupCompletedDefaultsKey)
                        onComplete()
                    }
                    .disabled(!isAddressValid || password.isEmpty)
                }
            }
        }
        .task {
            if let detectedAddress = await F50Configuration.discoverDeviceAddress() {
                address = detectedAddress
                discoveryMessage = "已发现 F50：\(detectedAddress)"
            } else {
                discoveryMessage = "未发现 F50，请确认已连接设备 Wi-Fi 后手动输入地址"
            }
            isDiscovering = false
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

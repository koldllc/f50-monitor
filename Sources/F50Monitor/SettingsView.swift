import SwiftUI
import F50Core

public struct SettingsView: View {
    @ObservedObject var fetcher: F50Fetcher
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var screenMirroringManager: ScreenMirroringManager
    var onOpenFileShare: () -> Void = {}
    var onOpenFeedback: () -> Void = {}
    var onOpenSMS: () -> Void = {}
    var onClose: () -> Void
    
    @State private var tempIP: String = ""
    @State private var tempPassword: String = ""
    @State private var tempUFIToken: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isUFITokenVisible: Bool = false
    @State private var tempInterval: Double = 2.0
    @State private var tempDisplayMode: MenuBarDisplayMode = .speeds
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @State private var isDiagnosingChannels = false
    @State private var channelDiagnosticResults: [DataChannelDiagnosticResult] = []
    @State private var selectedGroup: SettingsGroup = .general
    
    init(
        fetcher: F50Fetcher,
        updateManager: UpdateManager,
        screenMirroringManager: ScreenMirroringManager,
        onOpenFileShare: @escaping () -> Void = {},
        onOpenFeedback: @escaping () -> Void = {},
        onOpenSMS: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        self.fetcher = fetcher
        self.updateManager = updateManager
        self.screenMirroringManager = screenMirroringManager
        self.onOpenFileShare = onOpenFileShare
        self.onOpenFeedback = onOpenFeedback
        self.onOpenSMS = onOpenSMS
        self.onClose = onClose
    }

    private var isIPValid: Bool {
        F50Configuration.isValidAddress(tempIP)
    }

    private enum SettingsGroup: String, CaseIterable, Identifiable {
        case general = "通用"
        case connection = "连接"
        case sharing = "文件共享"
        case mirroring = "无线投屏"
        case updates = "软件更新"
        case diagnostics = "诊断与反馈"

        var id: Self { self }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .connection: "network"
            case .sharing: "folder"
            case .mirroring: "rectangle.on.rectangle"
            case .updates: "arrow.down.circle"
            case .diagnostics: "stethoscope"
            }
        }
    }

    private let groupTitleFont = Font.system(size: 14, weight: .semibold)
    private let itemTitleFont = Font.system(size: 13, weight: .medium)
    private let descriptionFont = Font.system(size: 11)
    private let groupSpacing: CGFloat = 16
    private let rowSpacing: CGFloat = 12
    private let detailSpacing: CGFloat = 4
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(F50Theme.blue)

                Spacer()

                Text("设置")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                Spacer()

                Color.clear
                    .frame(width: 48, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: 148)
                    .padding(10)

                Divider()

                ScrollView {
                    selectedSettings
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
            .frame(height: 420)

            Divider()

            HStack {
                Text("© 2026 Kold. All rights reserved.")
                    .font(descriptionFont)
                    .foregroundColor(.secondary)
                Spacer()
                Link("GitHub 项目链接", destination: URL(string: "https://github.com/koldllc/f50-monitor")!)
                    .font(descriptionFont)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack {
                Button("使用默认值") {
                    tempIP = "192.168.0.1"
                    tempPassword = F50Configuration.defaultCredential
                    tempUFIToken = F50Configuration.defaultCredential
                    tempInterval = F50Configuration.defaultRefreshInterval
                    tempDisplayMode = .speeds
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("保存") {
                    let finalURL = F50Configuration.normalizeBaseURL(tempIP)
                    fetcher.applyConfiguration(
                        baseURL: finalURL,
                        password: tempPassword,
                        ufiToken: tempUFIToken,
                        refreshInterval: tempInterval,
                        displayMode: tempDisplayMode
                    )
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .tint(F50Theme.blue)
                .disabled(!isIPValid)
            }
            .padding(16)
        }
        .frame(width: 680)
        .onAppear {
            tempIP = F50Configuration.displayAddress(from: fetcher.baseURLString)
            tempPassword = fetcher.password
            tempUFIToken = fetcher.ufiToken
            tempInterval = fetcher.refreshInterval
            tempDisplayMode = fetcher.displayMode
            launchAtLogin.refresh()
            screenMirroringManager.checkDependencies()
        }
        .alert("请求下载配置授权", isPresented: $screenMirroringManager.showPermissionAlert) {
            Button("允许并下载") {
                screenMirroringManager.downloadAndInstallStandaloneDependencies()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("无线投屏功能需要依赖官方独立组件包 (scrcpy + ADB)。\n\n点击“允许并下载”将自动在线下载并配置独立组件（无需安装 Homebrew 或终端操作）。")
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsGroup.allCases) { group in
                Button {
                    selectedGroup = group
                } label: {
                    Label(group.rawValue, systemImage: group.icon)
                        .font(itemTitleFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(selectedGroup == group ? .primary : .secondary)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectedGroup == group ? F50Theme.blue.opacity(0.14) : .clear)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var selectedSettings: some View {
        switch selectedGroup {
        case .general:
            generalSettings
        case .connection:
            connectionSettings
        case .sharing:
            fileSharingSettings
        case .mirroring:
            mirroringSettings
        case .updates:
            updateSettings
        case .diagnostics:
            diagnosticSettings
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: groupSpacing) {
            Text("通用")
                .font(groupTitleFont)

            VStack(alignment: .leading, spacing: detailSpacing) {
                HStack {
                    Text("登录时自动启动")
                        .font(itemTitleFont)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(launchAtLogin.isUpdating)
                }

                if launchAtLogin.requiresApproval {
                    HStack(spacing: 4) {
                        Text("需要在系统设置中允许")
                            .font(descriptionFont)
                            .lineSpacing(2)
                            .foregroundColor(.secondary)
                        Button("前往设置") {
                            launchAtLogin.openSystemSettings()
                        }
                        .buttonStyle(.link)
                        .font(descriptionFont)
                    }
                } else if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(descriptionFont)
                        .lineSpacing(2)
                        .foregroundColor(F50Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: rowSpacing) {
                Text("刷新与显示")
                    .font(groupTitleFont)

                HStack {
                    Text("自动刷新频率")
                        .font(itemTitleFont)
                    Spacer()
                    Picker("", selection: $tempInterval) {
                        Text("1 秒").tag(1.0)
                        Text("3 秒（推荐节能）").tag(3.0)
                        Text("5 秒（极简降温）").tag(5.0)
                        Text("10 秒（超低负载）").tag(10.0)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                HStack {
                    Text("菜单栏显示模式")
                        .font(itemTitleFont)
                    Spacer()
                    Picker("", selection: $tempDisplayMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: tempDisplayMode) { newMode in
                        fetcher.displayMode = newMode
                    }
                }
            }
        }
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: groupSpacing) {
            Text("连接")
                .font(groupTitleFont)

            settingField("设备 IP / 域名") {
                TextField("192.168.0.1 或域名", text: $tempIP)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(itemTitleFont)
                    .frame(width: 220)
            }

            if !tempIP.isEmpty && !isIPValid {
                Text("请输入正确的 IP 地址或域名（例如 192.168.0.1 或 f50.example.com）")
                    .font(descriptionFont)
                    .lineSpacing(2)
                    .foregroundColor(F50Theme.red)
            }

            settingField("中兴后台口令") {
                credentialField(isVisible: $isPasswordVisible, placeholder: "例如 admin", text: $tempPassword)
            }

            settingField("UFI 后台口令") {
                credentialField(isVisible: $isUFITokenVisible, placeholder: "可选", text: $tempUFIToken)
            }
        }
    }

    private func settingField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(itemTitleFont)
            Spacer(minLength: 16)
            content()
        }
    }

    private func credentialField(isVisible: Binding<Bool>, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            if isVisible.wrappedValue {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(itemTitleFont)
            } else {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(itemTitleFont)
            }

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .font(itemTitleFont)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220)
    }

    private var fileSharingSettings: some View {
        VStack(alignment: .leading, spacing: groupSpacing) {
            Text("文件共享")
                .font(groupTitleFont)

            HStack {
                VStack(alignment: .leading, spacing: detailSpacing) {
                    Text("访问 F50 共享文件")
                        .font(itemTitleFont)
                    Text("在 App 内浏览，支持拖拽上传和下载")
                        .font(descriptionFont)
                        .lineSpacing(2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("打开") {
                    onOpenFileShare()
                }
                .buttonStyle(.borderedProminent)
                .tint(F50Theme.blue)
            }
        }
    }

    private var mirroringSettings: some View {
        VStack(alignment: .leading, spacing: groupSpacing) {
            Text("无线投屏")
                .font(groupTitleFont)

                HStack {
                    Text("启用无线投屏功能")
                        .font(itemTitleFont)

                    Spacer()

                    Toggle("", isOn: $screenMirroringManager.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if screenMirroringManager.isEnabled {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        HStack {
                            Text("依赖组件状态：")
                                .font(itemTitleFont)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Label("adb", systemImage: screenMirroringManager.hasAdb ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(screenMirroringManager.hasAdb ? F50Theme.green : F50Theme.red)
                                    .font(descriptionFont.weight(.semibold))
                                Label("scrcpy", systemImage: screenMirroringManager.hasScrcpy ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(screenMirroringManager.hasScrcpy ? F50Theme.green : F50Theme.red)
                                    .font(descriptionFont.weight(.semibold))
                            }
                        }

                        if !screenMirroringManager.isDependenciesInstalled {
                            VStack(alignment: .leading, spacing: detailSpacing) {
                                Text("未检测到投屏所需组件 (scrcpy 与 ADB)。")
                                    .font(descriptionFont)
                                    .lineSpacing(2)
                                    .foregroundColor(F50Theme.orange)

                                Button(action: {
                                    screenMirroringManager.requestInstallDependencies()
                                }) {
                                    HStack(spacing: 4) {
                                        if screenMirroringManager.isDownloadingDependencies {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.down.circle")
                                        }
                                        Text(screenMirroringManager.isDownloadingDependencies ? "正在下载配置中..." : "一键自动下载并配置组件")
                                    }
                                    .font(itemTitleFont)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(F50Theme.blue)
                                .disabled(screenMirroringManager.isDownloadingDependencies)
                            }
                        }

                        if let msg = screenMirroringManager.installStatusMessage ?? screenMirroringManager.statusMessage {
                            Text(msg)
                                .font(descriptionFont)
                                .lineSpacing(2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
    }

    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: groupSpacing) {
            Text("软件更新")
                .font(groupTitleFont)

                HStack {
                    Text("自动下载并安装新版本")
                        .font(itemTitleFont)

                    Spacer()

                    Toggle("", isOn: $updateManager.automaticallyInstallsUpdates)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    VStack(alignment: .leading, spacing: detailSpacing) {
                        Text("F50 Monitor v\(updateManager.currentVersion)")
                            .font(itemTitleFont)
                        Text(updateManager.statusText)
                            .font(descriptionFont)
                            .lineSpacing(2)
                            .foregroundColor(updateManager.availableVersion == nil ? .secondary : F50Theme.green)
                    }

                    Spacer()

                    if updateManager.availableVersion != nil {
                        Button("立即更新") {
                            updateManager.installAvailableUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(F50Theme.green)
                    } else {
                        Button("检查更新") {
                            updateManager.checkForUpdates(installAutomatically: false)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .disabled(updateManager.isBusy)
            }
    }

    private var diagnosticSettings: some View {
        VStack(alignment: .leading, spacing: groupSpacing) {
            Text("诊断与反馈")
                .font(groupTitleFont)

            VStack(alignment: .leading, spacing: detailSpacing) {
                Text("数据端口诊断")
                    .font(itemTitleFont)

                HStack {
                    Text("检测 80、5555、2333 是否可获取数据")
                        .font(descriptionFont)
                        .lineSpacing(2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(isDiagnosingChannels ? "检测中…" : "开始检测") {
                        diagnoseDataChannels()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDiagnosingChannels)
                }

                ForEach(channelDiagnosticResults) { result in
                    HStack(spacing: 6) {
                        Image(systemName: result.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.isAvailable ? F50Theme.green : F50Theme.red)
                        Text(result.name)
                            .font(itemTitleFont)
                        Text(result.detail)
                            .font(descriptionFont)
                            .lineSpacing(2)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: detailSpacing) {
                    Text("问题反馈与设备适配")
                        .font(itemTitleFont)
                    Text("提交使用问题、Bug 或新设备适配")
                        .font(descriptionFont)
                        .lineSpacing(2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("去反馈") {
                    onOpenFeedback()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func diagnoseDataChannels() {
        isDiagnosingChannels = true
        channelDiagnosticResults = []
        Task { @MainActor in
            channelDiagnosticResults = await fetcher.diagnoseDataChannels()
            isDiagnosingChannels = false
        }
    }

}

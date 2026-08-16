import SwiftUI
import F50Core

public struct SettingsView: View {
    @ObservedObject var fetcher: F50Fetcher
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var screenMirroringManager: ScreenMirroringManager
    var onClose: () -> Void
    
    @State private var tempURL: String = ""
    @State private var tempPassword: String = ""
    @State private var tempUFIToken: String = ""
    @State private var tempInterval: Double = 2.0
    @State private var tempDisplayMode: MenuBarDisplayMode = .speeds
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    
    init(fetcher: F50Fetcher, updateManager: UpdateManager, screenMirroringManager: ScreenMirroringManager, onClose: @escaping () -> Void) {
        self.fetcher = fetcher
        self.updateManager = updateManager
        self.screenMirroringManager = screenMirroringManager
        self.onClose = onClose
    }


    private var trimmedURL: String {
        tempURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isURLValid: Bool {
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return url.host?.isEmpty == false
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onClose) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(F50Theme.blue)

                Spacer()

                Text("设置")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer()

                Color.clear
                    .frame(width: 48, height: 1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("登录时自动启动")
                        .font(.system(size: 12, weight: .semibold))

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
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Button("前往设置") {
                            launchAtLogin.openSystemSettings()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                    }
                } else if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundColor(F50Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            VStack(alignment: .leading, spacing: 8) {
                Text("连接设置")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("后台 API 地址")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("http://192.168.0.1:2333", text: $tempURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    if !isURLValid {
                        Text("请输入包含 http:// 或 https:// 的有效地址")
                            .font(.system(size: 10))
                            .foregroundColor(F50Theme.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("路由器管理密码 (Port 80)")
                        .font(.system(size: 12, weight: .semibold))
                    SecureField("例如 admin", text: $tempPassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("UFI-TOOLS 登录口令 (Port 2333)")
                        .font(.system(size: 12, weight: .semibold))
                    SecureField("例如 admin", text: $tempUFIToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            VStack(alignment: .leading, spacing: 8) {
                Text("刷新与显示（节能优化）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack {
                    Text("自动刷新频率")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("", selection: $tempInterval) {
                        Text("3 秒（推荐节能）").tag(3.0)
                        Text("5 秒（极简降温）").tag(5.0)
                        Text("10 秒（超低负载）").tag(10.0)
                        Text("2 秒").tag(2.0)
                        Text("1 秒").tag(1.0)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Text("适当拉长刷新间隔（如 3~5 秒）可大幅降低 F50 设备芯片 CPU 占用率与发热。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                HStack {
                    Text("菜单栏显示模式")
                        .font(.system(size: 12, weight: .semibold))
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
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            VStack(alignment: .leading, spacing: 8) {
                Text("无线投屏 (scrcpy)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack {
                    Text("启用无线投屏功能")
                        .font(.system(size: 12, weight: .semibold))

                    Spacer()

                    Toggle("", isOn: $screenMirroringManager.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if screenMirroringManager.isEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("依赖组件状态：")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Label("adb", systemImage: screenMirroringManager.hasAdb ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(screenMirroringManager.hasAdb ? F50Theme.green : F50Theme.red)
                                    .font(.system(size: 10, weight: .semibold))
                                Label("scrcpy", systemImage: screenMirroringManager.hasScrcpy ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(screenMirroringManager.hasScrcpy ? F50Theme.green : F50Theme.red)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }

                        if !screenMirroringManager.isDependenciesInstalled {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("未检测到投屏所需组件 (scrcpy 与 ADB)。")
                                    .font(.system(size: 10))
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
                                    .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(F50Theme.blue)
                                .disabled(screenMirroringManager.isDownloadingDependencies)
                            }
                        }

                        if let msg = screenMirroringManager.installStatusMessage ?? screenMirroringManager.statusMessage {
                            Text(msg)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            VStack(alignment: .leading, spacing: 8) {
                Text("软件更新")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack {
                    Text("自动下载并安装新版本")
                        .font(.system(size: 12, weight: .semibold))

                    Spacer()

                    Toggle("", isOn: $updateManager.automaticallyInstallsUpdates)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("F50 Monitor v\(updateManager.currentVersion)")
                            .font(.system(size: 11, weight: .semibold))
                        Text(updateManager.statusText)
                            .font(.system(size: 10))
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
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            HStack {
                Text("更新来源：GitHub Releases")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Link("GitHub 开源项目", destination: URL(string: "https://github.com/koldllc/f50-monitor")!)
                    .font(.system(size: 10))
            }

            HStack {
                Button("使用默认值") {
                    tempURL = F50Configuration.defaultBaseURL
                    tempPassword = F50Configuration.defaultCredential
                    tempUFIToken = F50Configuration.defaultCredential
                    tempInterval = F50Configuration.defaultRefreshInterval
                    tempDisplayMode = .speeds
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("保存") {
                    fetcher.applyConfiguration(
                        baseURL: trimmedURL,
                        password: tempPassword,
                        ufiToken: tempUFIToken,
                        refreshInterval: tempInterval,
                        displayMode: tempDisplayMode
                    )
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .tint(F50Theme.blue)
                .disabled(!isURLValid)
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            tempURL = fetcher.baseURLString
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
}



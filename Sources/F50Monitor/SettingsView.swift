import SwiftUI

public struct SettingsView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onClose: () -> Void
    
    @State private var tempURL: String = ""
    @State private var tempPassword: String = ""
    @State private var tempUFIToken: String = ""
    @State private var tempInterval: Double = 2.0
    @State private var tempDisplayMode: MenuBarDisplayMode = .full
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    
    public init(fetcher: F50Fetcher, onClose: @escaping () -> Void) {
        self.fetcher = fetcher
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
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)

                Spacer()

                Text("设置")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Color.clear
                    .frame(width: 48, height: 1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("连接")
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
                            .foregroundColor(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("路由器管理密码")
                        .font(.system(size: 12, weight: .semibold))
                    SecureField("例如 admin", text: $tempPassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("UFI-TOOLS 登录口令（可选）")
                        .font(.system(size: 12, weight: .semibold))
                    SecureField("例如 admin", text: $tempUFIToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            VStack(alignment: .leading, spacing: 8) {
                Text("刷新与显示")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack {
                    Text("自动刷新频率")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("", selection: $tempInterval) {
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                        Text("3 秒").tag(3.0)
                        Text("5 秒").tag(5.0)
                        Text("10 秒").tag(10.0)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

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
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )) {
                    Text("登录时自动启动")
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.switch)
                .disabled(launchAtLogin.isUpdating)

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
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            Spacer()

            HStack {
                Button("使用默认值") {
                    tempURL = F50Configuration.defaultBaseURL
                    tempPassword = F50Configuration.defaultCredential
                    tempUFIToken = F50Configuration.defaultCredential
                    tempInterval = F50Configuration.defaultRefreshInterval
                    tempDisplayMode = .full
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
                .tint(.blue)
                .disabled(!isURLValid)
            }
        }
        .padding(16)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            tempURL = fetcher.baseURLString
            tempPassword = fetcher.password
            tempUFIToken = fetcher.ufiToken
            tempInterval = fetcher.refreshInterval
            tempDisplayMode = fetcher.displayMode
            launchAtLogin.refresh()
        }
    }
}

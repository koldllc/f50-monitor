import SwiftUI
import F50Core

struct InitialSetupView: View {
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
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(F50Theme.blue)

            VStack(alignment: .leading, spacing: 6) {
                Text("欢迎使用 F50 Monitor")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("先连接你的 F50 设备，之后可随时在设置中修改。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("设备地址")
                    .font(.system(size: 13, weight: .semibold))
                TextField("例如 192.168.0.1 或 f50.example.com", text: $address)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 5) {
                    if isDiscovering {
                        ProgressView().controlSize(.small)
                    }
                    Text(discoveryMessage)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                if !address.isEmpty && !isAddressValid {
                    Text("请输入正确的 IP 地址或域名")
                        .font(.system(size: 11))
                        .foregroundColor(F50Theme.red)
                }

                Text("后台密码")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Group {
                        if isPasswordVisible {
                            TextField("请输入后台密码", text: $password)
                        } else {
                            SecureField("请输入后台密码", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                Text("UFI 后台口令为可选项，可稍后在设置中单独填写。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
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
                .buttonStyle(.borderedProminent)
                .tint(F50Theme.blue)
                .disabled(!isAddressValid || password.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 400)
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

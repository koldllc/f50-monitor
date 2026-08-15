import SwiftUI
import F50Core

/// iOS 设置：连接参数、刷新频率、流量校准
struct SettingsView: View {
    @ObservedObject var fetcher: F50Fetcher
    @State private var tempURL = ""
    @State private var tempPassword = ""
    @State private var tempUFIToken = ""
    @State private var tempInterval: Double = 2.0
    @State private var showSavedNotice = false

    private var trimmedURL: String {
        tempURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isURLValid: Bool {
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return url.host?.isEmpty == false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("连接设置") {
                    TextField("后台 API 地址", text: $tempURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if !isURLValid {
                        Text("请输入包含 http:// 或 https:// 的有效地址")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    SecureField("路由器管理密码 (80 端口)", text: $tempPassword)
                    SecureField("UFI-TOOLS 登录口令 (2333 端口)", text: $tempUFIToken)
                }

                Section("刷新频率") {
                    Picker("自动刷新", selection: $tempInterval) {
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                        Text("3 秒（推荐）").tag(3.0)
                        Text("5 秒").tag(5.0)
                        Text("10 秒").tag(10.0)
                    }
                    Text("适当拉长刷新间隔可降低设备芯片占用与发热")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button {
                        fetcher.applyConfiguration(
                            baseURL: trimmedURL,
                            password: tempPassword,
                            ufiToken: tempUFIToken,
                            refreshInterval: tempInterval,
                            displayMode: fetcher.displayMode
                        )
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation { showSavedNotice = true }
                    } label: {
                        HStack {
                            Spacer()
                            Text(showSavedNotice ? "已保存 ✓" : "保存设置")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(!isURLValid)
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.6.2")
                    Link("GitHub 项目", destination: URL(string: "https://github.com/koldllc/f50-monitor")!)
                }
            }
            .navigationTitle("设置")
            .onAppear {
                tempURL = fetcher.baseURLString
                tempPassword = fetcher.password
                tempUFIToken = fetcher.ufiToken
                tempInterval = fetcher.refreshInterval
            }
            .overlay(alignment: .bottom) {
                if showSavedNotice {
                    Text("配置修改已保存")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.green.opacity(0.9)))
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showSavedNotice = false }
                            }
                        }
                }
            }
        }
    }
}

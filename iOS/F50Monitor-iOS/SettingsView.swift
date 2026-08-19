import SwiftUI
import F50Core

/// iOS 设置：连接参数、刷新频率、关于信息
struct SettingsView: View {
    @ObservedObject var fetcher: F50Fetcher
    @State private var tempIP = ""
    @State private var tempPassword = ""
    @State private var tempUFIToken = ""
    @State private var isPasswordVisible = false
    @State private var isUFITokenVisible = false
    @State private var tempInterval: Double = 2.0
    @State private var isInitialized = false

    private var isIPValid: Bool {
        F50Configuration.isValidAddress(tempIP)
    }

    private func autoSave() {
        guard isInitialized, isIPValid else { return }
        let finalURL = F50Configuration.normalizeBaseURL(tempIP)
        fetcher.applyConfiguration(
            baseURL: finalURL,
            password: tempPassword,
            ufiToken: tempUFIToken,
            refreshInterval: tempInterval,
            displayMode: fetcher.displayMode
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("连接设置") {
                    // 设备 IP / 域名
                    HStack {
                        Text("设备 IP / 域名")
                            .foregroundColor(.primary)
                            .fixedSize()
                        Spacer(minLength: 12)
                        TextField("192.168.0.1 或域名", text: $tempIP)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    if !tempIP.isEmpty && !isIPValid {
                        Text("请输入正确的 IP 地址或域名（例如 192.168.0.1 或 f50.example.com）")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // 中兴后台口令 (Port 80)
                    HStack {
                        Text("中兴后台口令")
                            .foregroundColor(.primary)
                            .fixedSize()
                        Spacer(minLength: 12)
                        if isPasswordVisible {
                            TextField("中兴后台口令", text: $tempPassword)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("中兴后台口令", text: $tempPassword)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                    }

                    // UFI后台口令 (Port 2333)
                    HStack {
                        Text("UFI后台口令")
                            .foregroundColor(.primary)
                            .fixedSize()
                        Spacer(minLength: 12)
                        if isUFITokenVisible {
                            TextField("UFI后台口令", text: $tempUFIToken)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("UFI后台口令", text: $tempUFIToken)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            isUFITokenVisible.toggle()
                        } label: {
                            Image(systemName: isUFITokenVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section {
                    Picker("自动刷新频率", selection: $tempInterval) {
                        Text("1 秒").tag(1.0)
                        Text("3 秒（推荐节能）").tag(3.0)
                        Text("5 秒（极简降温）").tag(5.0)
                        Text("10 秒（超低负载）").tag(10.0)
                    }
                } header: {
                    Text("刷新与节能")
                } footer: {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.1"
                    VStack(spacing: 6) {
                        Text("F50 Monitor v\(version)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        Link("GitHub 项目链接", destination: URL(string: "https://github.com/koldllc/f50-monitor")!)
                            .font(.system(size: 12))

                        Text("© 2026 Kold. All rights reserved.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 28)
                }
            }
            .navigationTitle("设置")
            .onAppear {
                tempIP = F50Configuration.displayAddress(from: fetcher.baseURLString)
                tempPassword = fetcher.password
                tempUFIToken = fetcher.ufiToken
                tempInterval = fetcher.refreshInterval
                DispatchQueue.main.async {
                    isInitialized = true
                }
            }
            .onChange(of: tempIP) { _ in autoSave() }
            .onChange(of: tempPassword) { _ in autoSave() }
            .onChange(of: tempUFIToken) { _ in autoSave() }
            .onChange(of: tempInterval) { _ in autoSave() }
        }
    }
}

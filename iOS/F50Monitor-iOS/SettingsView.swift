import SwiftUI
import UIKit
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
    @State private var isShowingFeedback = false
    @State private var isShowingFileShareHelp = false

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

                    // UFI后台口令
                    HStack {
                        Text("UFI后台口令")
                            .foregroundColor(.primary)
                            .fixedSize()
                        Spacer(minLength: 12)
                        if isUFITokenVisible {
                            TextField("可选", text: $tempUFIToken)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("可选", text: $tempUFIToken)
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
                    Toggle("开启演示模式 (Demo Mode)", isOn: $fetcher.isDemoMode)
                } header: {
                    Text("演示与审核")
                } footer: {
                    Text("开启后将展示全套模拟 5G 信号、流量用量与短信数据，无需物理 F50 硬件即可完整体验 App 全部功能。")
                }

                Section {
                    Picker("前台自动刷新频率", selection: $tempInterval) {
                        Text("1 秒").tag(1.0)
                        Text("3 秒（推荐节能）").tag(3.0)
                        Text("5 秒（极简降温）").tag(5.0)
                        Text("10 秒（超低负载）").tag(10.0)
                    }
                } header: {
                    Text("刷新与节能")
                } footer: {
                    Text("后台数据更新基于 iOS 系统智能调度机制（BGAppRefreshTask），适时更新小组件与数据缓存，具体频次由系统根据电量与使用情况决定。")
                }

                Section("文件共享") {
                    Button {
                        guard let url = F50Configuration.fileShareURL(from: fetcher.baseURLString) else { return }
                        UIApplication.shared.open(url) { supported in
                            if !supported { isShowingFileShareHelp = true }
                        }
                    } label: {
                        Label("打开 F50 共享文件", systemImage: "folder")
                    }
                } footer: {
                    Text("通过 F50 已开启的 SMB 文件共享访问设备存储。若系统未直接打开，请在“文件”App 的“连接服务器”中输入设备地址。")
                }

                Section("帮助与反馈") {
                    Button {
                        isShowingFeedback = true
                    } label: {
                        Label("问题反馈与设备适配", systemImage: "ladybug.fill")
                    }
                }

                Section {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2.1"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "8"
                    VStack(spacing: 6) {
                        Text("F50 Monitor v\(version) (\(build))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            Link("GitHub 项目", destination: URL(string: "https://github.com/koldllc/f50-monitor")!)
                                .font(.system(size: 12))

                            Link("隐私政策", destination: URL(string: "https://github.com/koldllc/f50-monitor/blob/main/docs/PRIVACY_POLICY.md")!)
                                .font(.system(size: 12))
                        }

                        Text("© 2026 Kold. All rights reserved.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("设置")
            .sheet(isPresented: $isShowingFeedback) {
                DeviceFeedbackView(fetcher: fetcher) {
                    isShowingFeedback = false
                }
            }
            .alert("在“文件”App 中连接 F50", isPresented: $isShowingFileShareHelp) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("打开“文件”App → 右上角更多 → 连接服务器，输入 \(F50Configuration.fileShareURL(from: fetcher.baseURLString)?.absoluteString ?? "smb://192.168.0.1")。")
            }
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

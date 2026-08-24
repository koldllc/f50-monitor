import SwiftUI
import UIKit
import F50Core
import UniformTypeIdentifiers

enum IOSFileSharingPreferences {
    static let enabledDefaultsKey = "F50_iOS_FileSharingEnabled"
}

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
    @State private var isShowingFileShare = false
    @AppStorage(IOSFileSharingPreferences.enabledDefaultsKey) private var isFileSharingEnabled = true

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

                Section {
                    Toggle("启用文件共享功能", isOn: $isFileSharingEnabled)

                    if isFileSharingEnabled {
                        Button {
                            openFileShareInFilesApp()
                        } label: {
                            Label("在“文件”App 中打开", systemImage: "folder.badge.gearshape")
                        }
                    }
                } header: {
                    Text("文件共享")
                } footer: {
                    Text("通过系统文件选择器在本机与 F50 SMB 共享之间传输文件；此开关不会修改设备端 SMB 设置。")
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

                Section {
                    Toggle("开启演示模式 (Demo Mode)", isOn: $fetcher.isDemoMode)
                } header: {
                    Text("演示与审核")
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $isShowingFeedback) {
                DeviceFeedbackView(fetcher: fetcher) {
                    isShowingFeedback = false
                }
            }
            .sheet(isPresented: $isShowingFileShare) {
                IOSFileShareView(fetcher: fetcher)
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

    private func openFileShareInFilesApp() {
        guard let url = F50Configuration.fileShareURL(from: fetcher.baseURLString) else { return }
        UIApplication.shared.open(url) { supported in
            if !supported { isShowingFileShareHelp = true }
        }
    }
}

private struct IOSFilePickerRequest: Identifiable {
    enum Kind: Equatable {
        case uploadSource
        case downloadSource
        case uploadDestination
        case downloadDestination
    }

    let id = UUID()
    let kind: Kind
    var urls: [URL] = []
}

struct IOSFileShareView: View {
    @ObservedObject var fetcher: F50Fetcher
    @Environment(\.dismiss) private var dismiss
    @State private var pickerRequest: IOSFilePickerRequest?
    @State private var statusMessage: String?

    private var shareURL: URL? {
        F50Configuration.fileShareURL(from: fetcher.baseURLString)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        pickerRequest = IOSFilePickerRequest(kind: .uploadSource)
                    } label: {
                        Label("上传到 F50", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        pickerRequest = IOSFilePickerRequest(kind: .downloadSource)
                    } label: {
                        Label("从 F50 下载", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("文件传输")
                } footer: {
                    Text("上传时先选择本机文件，再选择 F50 共享目录；下载时先从 F50 选择文件，再选择本机保存位置。")
                }

                Section {
                    Button {
                        guard let shareURL else { return }
                        UIApplication.shared.open(shareURL)
                    } label: {
                        Label("前往“文件”App 连接服务器", systemImage: "folder.badge.gearshape")
                    }
                } footer: {
                    Text("若选择器中没有显示 F50，请先在“文件”App 中通过“连接服务器”添加 \(shareURL?.absoluteString ?? "smb://192.168.0.1")。")
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("F50 文件共享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $pickerRequest) { request in
                IOSDocumentPicker(
                    request: request,
                    shareURL: shareURL,
                    onPick: { urls in
                        pickerRequest = nil
                        handleSelection(urls, for: request.kind)
                    },
                    onCancel: {
                        pickerRequest = nil
                    }
                )
            }
        }
    }

    private func handleSelection(_ urls: [URL], for kind: IOSFilePickerRequest.Kind) {
        guard !urls.isEmpty else { return }
        switch kind {
        case .uploadSource:
            presentNext(IOSFilePickerRequest(kind: .uploadDestination, urls: urls))
        case .downloadSource:
            presentNext(IOSFilePickerRequest(kind: .downloadDestination, urls: urls))
        case .uploadDestination:
            statusMessage = "文件已上传"
        case .downloadDestination:
            statusMessage = "文件已保存"
        }
    }

    private func presentNext(_ request: IOSFilePickerRequest) {
        pickerRequest = nil
        DispatchQueue.main.async {
            pickerRequest = request
        }
    }
}

private struct IOSDocumentPicker: UIViewControllerRepresentable {
    let request: IOSFilePickerRequest
    let shareURL: URL?
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        switch request.kind {
        case .uploadSource, .downloadSource:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.allowsMultipleSelection = true
            if request.kind == .downloadSource {
                picker.directoryURL = shareURL
            }
        case .uploadDestination, .downloadDestination:
            picker = UIDocumentPickerViewController(forExporting: request.urls, asCopy: true)
            if request.kind == .uploadDestination {
                picker.directoryURL = shareURL
            }
        }
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

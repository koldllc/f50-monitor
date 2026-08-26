#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#elseif os(iOS)
import UIKit
import PhotosUI
public typealias PlatformImage = UIImage
#endif
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Category Color Helper

extension FeedbackCategory {
    public var accentColor: Color {
        switch self {
        case .deviceAdaptation: return F50Theme.blue
        case .connectionFailure: return F50Theme.orange
        case .missingData: return F50Theme.purple
        case .inaccurateData: return F50Theme.cyan
        case .smsIssue: return F50Theme.green
        case .screenMirroringIssue: return Color.indigo
        case .featureSuggestion: return Color.yellow
        case .appBug: return F50Theme.red
        }
    }
}

// MARK: - Router Login Diagnostic

private struct RouterLoginDiagnosticSheet: View {
    let routerURL: URL?
    let onSessionReady: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sessionCookie: String? = nil
    @State private var loginStatus: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let routerURL {
                    RouterLoginWebView(url: routerURL) { cookie in
                        sessionCookie = cookie
                        loginStatus = nil
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("后台地址无效")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("请在上方完成原厂后台登录，再继续诊断。")
                        .font(.system(size: 13, weight: .semibold))
                    Text("登录密码与 Cookie 仅暂存于本次诊断会话，不会写入反馈报告或上传。")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let loginStatus {
                    Text(loginStatus)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                Button("已完成登录，继续诊断") {
                    guard let sessionCookie, !sessionCookie.isEmpty else {
                        loginStatus = "未检测到登录会话，请完成登录后重试。"
                        return
                    }
                    onSessionReady(sessionCookie)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(routerURL == nil)
            }
            .padding()
            .navigationTitle("原厂后台登录")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            #else
            .frame(minWidth: 560, minHeight: 620)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            #endif
        }
    }
}

#if os(iOS)
private struct RouterLoginWebView: UIViewRepresentable {
    let url: URL
    let onCookieChanged: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(host: url.host ?? "", onCookieChanged: onCookieChanged) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.observeCookies(in: configuration.websiteDataStore.httpCookieStore)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
private struct RouterLoginWebView: NSViewRepresentable {
    let url: URL
    let onCookieChanged: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(host: url.host ?? "", onCookieChanged: onCookieChanged) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.observeCookies(in: configuration.websiteDataStore.httpCookieStore)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

private final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    private let host: String
    private let onCookieChanged: (String) -> Void
    private weak var cookieStore: WKHTTPCookieStore?

    init(host: String, onCookieChanged: @escaping (String) -> Void) {
        self.host = host
        self.onCookieChanged = onCookieChanged
    }

    deinit {
        cookieStore?.remove(self)
    }

    func observeCookies(in cookieStore: WKHTTPCookieStore) {
        self.cookieStore = cookieStore
        cookieStore.add(self)
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        publishCookies(from: cookieStore)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        publishCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
    }

    private func publishCookies(from cookieStore: WKHTTPCookieStore) {
        guard !host.isEmpty else { return }
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let matchingCookies = cookies.filter { $0.domain == self.host || $0.domain == ".\(self.host)" }
            guard !matchingCookies.isEmpty else { return }
            let header = matchingCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            DispatchQueue.main.async {
                self.onCookieChanged(header)
            }
        }
    }
}

// MARK: - Device Feedback View

public struct DeviceFeedbackView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onClose: () -> Void

    @State private var selectedCategory: FeedbackCategory = .deviceAdaptation
    @State private var deviceModel: String = ""
    @State private var contact: String = ""
    @State private var userNotes: String = ""
    @State private var attachedImage: PlatformImage? = nil
    @State private var attachedImageBase64: String? = nil
    @State private var attachedImageSizeKB: Double = 0.0

    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    #endif

    @State private var isProcessing: Bool = false
    @State private var probeProgress: Double = 0.0
    @State private var probeStatusText: String = ""
    @State private var submitSuccess: Bool = false
    @State private var statusFeedbackMessage: String? = nil
    @State private var createdIssueURL: String? = nil
    @State private var showRouterLoginDiagnostic = false
    @State private var routerLoginSessionCookie: String? = nil

    private let webhookURL = URL(string: "https://feedback-api.koldllc.com")!

    public init(fetcher: F50Fetcher, onClose: @escaping () -> Void) {
        self.fetcher = fetcher
        self.onClose = onClose
    }

    public var body: some View {
        Group {
        #if os(iOS)
            iOSBody
        #else
            macOSBody
        #endif
        }
        .sheet(isPresented: $showRouterLoginDiagnostic) {
            RouterLoginDiagnosticSheet(
                routerURL: routerLoginURL,
                onSessionReady: { cookie in
                    routerLoginSessionCookie = cookie
                    statusFeedbackMessage = "已获取网页登录会话。"
                }
            )
        }
    }

    private var routerLoginURL: URL? {
        let (routerBaseURL, _) = F50Configuration.resolveEndpoints(from: fetcher.baseURLString)
        return URL(string: routerBaseURL)
    }

    // MARK: - iOS Layout (Native HIG Compliant)
    #if os(iOS)
    private var iOSBody: some View {
        NavigationStack {
            Form {
                Section("反馈内容") {
                    categorySelectionCard
                    formFieldsCard
                }

                Section("附件") {
                    screenshotCardiOS
                }

                Section {
                    submitAndProgressCard
                }
            }
                .navigationTitle("问题反馈与设备适配")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        }
                    }

                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") {
                            hideKeyboard()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }

    // MARK: iOS Subviews

    private var categorySelectionCard: some View {
        Picker("反馈类型", selection: $selectedCategory) {
            ForEach(FeedbackCategory.allCases) { category in
                Label(category.rawValue, systemImage: category.iconName)
                    .tag(category)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var formFieldsCard: some View {
        HStack {
            Text("设备型号（必填）")
                .foregroundColor(.primary)
                .fixedSize()
            Spacer(minLength: 12)
            TextField("必填", text: $deviceModel)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isProcessing)
        }

        HStack {
            Text("联系方式")
                .foregroundColor(.primary)
                .fixedSize()
            Spacer(minLength: 12)
            TextField("选填", text: $contact)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isProcessing)
        }

        HStack(alignment: .top) {
            Text("问题描述")
                .foregroundColor(.primary)
                .fixedSize()
            TextEditor(text: $userNotes)
                .frame(minHeight: 88)
                .disabled(isProcessing)
        }
    }

    private var screenshotCardiOS: some View {
        Group {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack {
                    Text("问题截图")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(attachedImage == nil ? "选填" : "更换")
                        .foregroundColor(.secondary)
                }
            }

            if let img = attachedImage {
                HStack(spacing: 12) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    Text("已选择 1 张截图")

                    Spacer()

                    Button {
                        attachedImage = nil
                        attachedImageBase64 = nil
                        attachedImageSizeKB = 0.0
                        selectedPhotoItem = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            loadSelectedPhoto(newItem)
        }
    }

    private var submitAndProgressCard: some View {
        VStack(spacing: 12) {
            // 提交成功状态
            if submitSuccess {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(F50Theme.green)
                        Text(fetcher.isDemoMode ? "演示反馈已完成" : "反馈已成功送达！")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(F50Theme.green)
                    }

                    Text(fetcher.isDemoMode ? "本次演示仅在本机完成。" : "开发者将尽快跟进处理。")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)

                    if let issueUrl = createdIssueURL, let url = URL(string: issueUrl) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 12))
                                Text("查看反馈处理进度")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(F50Theme.blue)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            withAnimation {
                                submitSuccess = false
                                statusFeedbackMessage = nil
                                createdIssueURL = nil
                            }
                        } label: {
                            Text("再次提交新反馈")
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onClose()
                        } label: {
                            Text("完成")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(F50Theme.green)
                    }
                }
            } else {
                // 进行中进度展示
                if isProcessing {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(probeStatusText)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(probeProgress * 100))%")
                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                .foregroundColor(F50Theme.blue)
                        }
                        ProgressView(value: probeProgress, total: 1.0)
                            .tint(F50Theme.blue)
                    }
                }

                // 主发送按钮
                routerLoginDiagnosticButton

                Button {
                    startProbeAndSubmit()
                } label: {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isProcessing ? "正在提交..." : "提交反馈")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)

                // 错误信息展示
                if let msg = statusFeedbackMessage, !submitSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(F50Theme.orange)
                            .font(.system(size: 13))
                        Text(msg)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(F50Theme.orange)
                        Spacer()
                    }
                }
            }
        }
    }

    private var routerLoginDiagnosticButton: some View {
        Button {
            showRouterLoginDiagnostic = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: routerLoginSessionCookie == nil ? "lock.open" : "checkmark.shield.fill")
                Text(routerLoginSessionCookie == nil ? "登录原厂后台（可选）" : "已获取网页登录会话")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isProcessing || routerLoginURL == nil)
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    processAndAttachImage(image)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif

    // MARK: - macOS Layout (Compact Popover Compliant)
    #if os(macOS)
    private var macOSBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部导航栏
            HStack {
                Button(action: onClose) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(F50Theme.blue)

                Spacer()

                Text("问题反馈与设备适配")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer()

                Color.clear
                    .frame(width: 48, height: 1)
            }

            Divider()

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    // 1. 反馈类型选择
                    HStack {
                        Text("反馈类型")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Picker("", selection: $selectedCategory) {
                            ForEach(FeedbackCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.iconName)
                                    .tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 190, alignment: .trailing)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

                    // 2. 表单信息输入
                    VStack(alignment: .leading, spacing: 8) {
                        // 设备型号 (必填)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("设备型号（必填）")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                if !deviceModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(F50Theme.green)
                                }
                            }
                            TextField("必填", text: $deviceModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .disabled(isProcessing)
                        }

                        // 联系方式
                        VStack(alignment: .leading, spacing: 4) {
                            Text("联系方式")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            TextField("选填", text: $contact)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .disabled(isProcessing)
                        }

                        // 详细描述 (必填)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("问题描述")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                let count = userNotes.trimmingCharacters(in: .whitespacesAndNewlines).count
                                Text(count >= 4 ? "\(count) 字" : "至少 4 字")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(count >= 4 ? F50Theme.green : .secondary)
                            }

                            TextEditor(text: $userNotes)
                                .font(.system(size: 12))
                                .frame(height: 70)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2))
                                )
                                .disabled(isProcessing)

                            if userNotes.isEmpty {
                                Text("请描述问题现象或操作步骤")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.8))
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

                    // 3. 问题截图附加
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("问题截图 (选填)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Spacer()

                            Button {
                                selectImageFile()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "photo.badge.plus")
                                    Text(attachedImage == nil ? "添加截图" : "更换截图")
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(F50Theme.blue)
                        }

                        if let img = attachedImage {
                            HStack(spacing: 8) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 48)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

                                Text(String(format: "已添加 1 张截图 (%.1f KB)", attachedImageSizeKB))
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary)

                                Spacer()

                                Button {
                                    attachedImage = nil
                                    attachedImageBase64 = nil
                                    attachedImageSizeKB = 0.0
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                        }

                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

                    // 4. 提交进度展示
                    if isProcessing {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text(probeStatusText)
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(probeProgress * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(F50Theme.blue)
                            }
                            ProgressView(value: probeProgress, total: 1.0)
                                .progressViewStyle(.linear)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(F50Theme.blue.opacity(0.06)))
                    }

                    // 5. 操作与结果区
                    if submitSuccess {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(F50Theme.green)
                                    .font(.system(size: 14))
                                Text(fetcher.isDemoMode ? "演示反馈已完成" : "反馈发送成功！")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(F50Theme.green)
                            }

                            Text(fetcher.isDemoMode ? "本次演示仅在本机完成。" : "开发者将尽快跟进处理。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            if let issueUrl = createdIssueURL, let url = URL(string: issueUrl) {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link")
                                        Text("查看反馈处理进度")
                                        Image(systemName: "arrow.up.right")
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(F50Theme.blue)
                                }
                            }

                            HStack {
                                Button {
                                    submitSuccess = false
                                    statusFeedbackMessage = nil
                                } label: {
                                    Text("再次提交新反馈")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(F50Theme.green.opacity(0.08)))
                    } else {
                        Button {
                            showRouterLoginDiagnostic = true
                        } label: {
                            Label(
                                routerLoginSessionCookie == nil ? "登录原厂后台（可选）" : "已获取网页登录会话",
                                systemImage: routerLoginSessionCookie == nil ? "lock.open" : "checkmark.shield.fill"
                            )
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessing || routerLoginURL == nil)

                        Button {
                            startProbeAndSubmit()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane.fill")
                                Text("一键抓取并发送反馈")
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(F50Theme.blue)
                        .disabled(isProcessing)
                    }

                    // 错误提示
                    if let msg = statusFeedbackMessage, !submitSuccess {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(F50Theme.orange)
                            Text(msg)
                                .font(.system(size: 10.5))
                                .foregroundColor(F50Theme.orange)
                        }
                        .padding(.horizontal, 4)
                    }

                }
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
    }

    private func selectImageFile() {
        let panel = NSOpenPanel()
        panel.title = "选择问题截图"
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
                processAndAttachImage(image)
            }
        }
    }
    #endif

    // MARK: - Image Processing (Both Platforms)

    private func processAndAttachImage(_ image: PlatformImage) {
        let maxScreenshotBytes = 220 * 1024
        #if os(macOS)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return
        }
        var jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        if let data = jpegData, data.count > maxScreenshotBytes {
            jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.35])
        }
        guard let jpegData, jpegData.count <= maxScreenshotBytes else {
            statusFeedbackMessage = "截图过大（上限 220 KB），请裁剪后重试。"
            return
        }
        self.attachedImage = image
        self.attachedImageBase64 = jpegData.base64EncodedString()
        self.attachedImageSizeKB = Double(jpegData.count) / 1024.0
        #elseif os(iOS)
        var targetImage = image
        let maxDimension: CGFloat = 1600
        let size = targetImage.size
        if size.width > maxDimension || size.height > maxDimension {
            let ratio = min(maxDimension / size.width, maxDimension / size.height)
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            targetImage = renderer.image { _ in
                targetImage.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        var jpegData = targetImage.jpegData(compressionQuality: 0.7)
        if let data = jpegData, data.count > maxScreenshotBytes {
            jpegData = targetImage.jpegData(compressionQuality: 0.4)
        }
        if let data = jpegData, data.count > maxScreenshotBytes {
            jpegData = targetImage.jpegData(compressionQuality: 0.2)
        }
        guard let jpegData, jpegData.count <= maxScreenshotBytes else {
            statusFeedbackMessage = "截图过大（上限 220 KB），请裁剪后重试。"
            return
        }
        self.attachedImage = targetImage
        self.attachedImageBase64 = jpegData.base64EncodedString()
        self.attachedImageSizeKB = Double(jpegData.count) / 1024.0
        #endif
    }

    // MARK: - Actions & Submission

    private func startProbeAndSubmit() {
        let trimmedDevice = deviceModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDevice.isEmpty else {
            statusFeedbackMessage = "请填写「设备品牌与型号」，例如：中兴 F50 / 华为 CPE 等。"
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
            return
        }

        let trimmedNotes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNotes.count >= 4 else {
            statusFeedbackMessage = "请在「详细问题描述」中至少输入 4 个字符以提供复现说明。"
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
            return
        }

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        isProcessing = true
        probeProgress = 0.0
        probeStatusText = "正在收集运行状态与接口诊断..."
        statusFeedbackMessage = nil
        submitSuccess = false
        createdIssueURL = nil

        if fetcher.isDemoMode {
            probeStatusText = "正在完成演示反馈…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.isProcessing = false
                self.probeProgress = 1.0
                self.probeStatusText = "演示反馈已完成，未发送任何网络请求。"
                self.submitSuccess = true
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            }
            return
        }

        let appVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

        // 获取当前应用状态快照与脱敏环形日志
        let stateSnapshot = AppStateSnapshot(
            isOnline: fetcher.status.isOnline,
            networkType: fetcher.status.networkType,
            carrier: fetcher.status.carrier,
            currentBands: fetcher.status.currentBands,
            signalBar: fetcher.status.signalBar,
            rsrp: fetcher.status.rsrp,
            snr: fetcher.status.snr,
            rsrq: fetcher.status.rsrq,
            dlSpeed: fetcher.status.dlSpeed,
            ulSpeed: fetcher.status.ulSpeed,
            cpuUsage: fetcher.status.cpuUsage,
            memUsage: fetcher.status.memUsage,
            temperature: fetcher.status.temperature,
            qci: fetcher.status.qci,
            qosDl: fetcher.status.qosDl,
            qosUl: fetcher.status.qosUl,
            connectedDevices: fetcher.status.connectedDevices,
            trafficResetDay: fetcher.status.trafficResetDay,
            monthlyTotalBytes: fetcher.status.monthlyTotal,
            dailyTotalBytes: fetcher.status.dailyTotal,
            packageTotalBytes: fetcher.status.packageTotal,
            trafficLimitBytes: fetcher.status.trafficLimit,
            smsUnreadCount: fetcher.status.smsUnreadCount,
            lastErrorMessage: fetcher.status.errorMessage,
            lastSMSErrorMessage: fetcher.smsErrorMessage,
            firmwareVersion: fetcher.currentDiagnosticFirmwareVersion,
            activeChannelMode: fetcher.currentDiagnosticChannelMode,
            recentLogs: fetcher.getRecentLogs()
        )

        Task {
            // 1. 抓取接口探测数据（结合正式链路的 Token 候选与 Router Session Cookie）
            let reportResult = await DeviceDiagnosticProbe.shared.executeProbe(
                baseURLString: fetcher.baseURLString,
                category: selectedCategory,
                deviceModel: deviceModel,
                userNotes: userNotes,
                contact: contact,
                appState: stateSnapshot,
                screenshotBase64: attachedImageBase64,
                candidateTokens: fetcher.getCandidateTokensPublic(),
                sessionCookie: routerLoginSessionCookie ?? fetcher.currentSessionCookie,
                appVersion: appVer
            ) { progress, status in
                Task { @MainActor in
                    self.probeProgress = progress * 0.85
                    self.probeStatusText = status
                }
            }

            await MainActor.run {
                self.probeProgress = 0.9
                self.probeStatusText = "正在提交反馈数据..."
            }

            // 2. 自动直传 Cloudflare Worker
            do {
                let (success, msg, issueURL) = try await DeviceDiagnosticProbe.shared.submitReportRemote(
                    report: reportResult,
                    webhookURL: webhookURL
                )
                await MainActor.run {
                    self.isProcessing = false
                    if success {
                        self.submitSuccess = true
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        #endif
                        self.createdIssueURL = issueURL
                    } else {
                        self.statusFeedbackMessage = "提交失败: \(msg)"
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        #endif
                    }
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.statusFeedbackMessage = "网络连接失败: \(error.localizedDescription)"
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    #endif
                }
            }
        }
    }

}

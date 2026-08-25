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
    let onSessionReady: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sessionCookie: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let routerURL {
                    RouterLoginWebView(url: routerURL) { cookie in
                        sessionCookie = cookie
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

                Button("已完成登录，继续诊断") {
                    if let sessionCookie {
                        onSessionReady(sessionCookie)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sessionCookie == nil)
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

    func makeCoordinator() -> Coordinator { Coordinator(onCookieChanged: onCookieChanged) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
private struct RouterLoginWebView: NSViewRepresentable {
    let url: URL
    let onCookieChanged: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCookieChanged: onCookieChanged) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

private final class Coordinator: NSObject, WKNavigationDelegate {
    private let onCookieChanged: (String) -> Void

    init(onCookieChanged: @escaping (String) -> Void) {
        self.onCookieChanged = onCookieChanged
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let host = webView.url?.host else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let matchingCookies = cookies.filter { $0.domain == host || $0.domain == ".\(host)" }
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

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedCategory: FeedbackCategory = .deviceAdaptation
    @State private var deviceModel: String = ""
    @State private var contact: String = ""
    @State private var userNotes: String = ""
    @State private var attachedImage: PlatformImage? = nil
    @State private var attachedImageBase64: String? = nil
    @State private var attachedImageSizeKB: Double = 0.0

    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCategoryPickerSheet: Bool = false
    #endif

    @State private var isProcessing: Bool = false
    @State private var probeProgress: Double = 0.0
    @State private var probeStatusText: String = ""
    @State private var report: DeviceDiagnosticReport? = nil
    @State private var showDetails: Bool = false
    @State private var showPrivacyInfo: Bool = false
    @State private var submitSuccess: Bool = false
    @State private var statusFeedbackMessage: String? = nil
    @State private var createdIssueURL: String? = nil
    @State private var showCopiedToast: Bool = false
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
                    statusFeedbackMessage = "已获取网页登录会话；提交时将用该会话探测接口。"
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
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        // 1. 顶部说明卡片
                        privacyBannerCard

                        // 2. 反馈类型选择与快捷提示
                        categorySelectionCard

                        // 3. 表单信息输入 (设备型号必填、联系方式选填、详细描述必填)
                        formFieldsCard

                        // 4. 截图附加卡片 (iOS 原生相册选择)
                        screenshotCardiOS

                        // 5. 诊断探测与提交卡片
                        submitAndProgressCard

                        // 6. 脱敏诊断快照与预览
                        diagnosticPreviewCard

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
                .sheet(isPresented: $showCategoryPickerSheet) {
                    categoryPickerSheetView
                }

                // 复制成功浮动提示
                if showCopiedToast {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(F50Theme.green)
                        Text("已复制到剪贴板")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(F50Theme.cardBackground(for: colorScheme))
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 3)
                    )
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: iOS Subviews

    private var privacyBannerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(F50Theme.blue)

                Text("数据安全与隐私保护")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPrivacyInfo.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(showPrivacyInfo ? "收起" : "说明")
                        Image(systemName: showPrivacyInfo ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(F50Theme.blue)
                }
            }

            Text("点击发送时，App 将自动对当前连接网关进行只读探测并采集设备型号与指标。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if showPrivacyInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().padding(.vertical, 2)
                    Label("后台登录口令、Token、Wi-Fi 密钥已全量掩码 (******)", systemImage: "checkmark.shield")
                    Label("短信正文与敏感内容已自动过滤脱敏", systemImage: "checkmark.shield")
                    Label("MAC 地址与 IMEI 串号已做中间隐藏掩码", systemImage: "checkmark.shield")
                }
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(F50Theme.cardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(F50Theme.cardBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private var categorySelectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("反馈类型", systemImage: "square.grid.2x2")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Text("点击更换")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Button {
                showCategoryPickerSheet = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(selectedCategory.accentColor.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: selectedCategory.iconName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(selectedCategory.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedCategory.rawValue)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        Text(selectedCategory.placeholderHint)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(F50Theme.controlBackground(for: colorScheme))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(F50Theme.cardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(F50Theme.cardBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private var categoryPickerSheetView: some View {
        NavigationStack {
            List {
                Section("选择符合您遇到的问题类型") {
                    ForEach(FeedbackCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                            showCategoryPickerSheet = false
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(category.accentColor.opacity(0.15))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: category.iconName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(category.accentColor)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.rawValue)
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(category.placeholderHint)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if selectedCategory == category {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(F50Theme.blue)
                                        .font(.system(size: 18))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("选择反馈类型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showCategoryPickerSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var formFieldsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 设备型号 (必填)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("设备品牌与型号", systemImage: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("(必填)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(F50Theme.blue)

                    Spacer()

                    if !deviceModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(F50Theme.green)
                    }
                }

                HStack {
                    TextField("例如：中兴 F50 / F30 Pro / 华为 CPE / 展锐 MiFi", text: $deviceModel)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isProcessing)

                    if !deviceModel.isEmpty {
                        Button {
                            deviceModel = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(F50Theme.controlBackground(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    !deviceModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? F50Theme.blue.opacity(0.3)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                )
            }

            // 联系方式
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("联系方式", systemImage: "person.crop.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("选填，便于跟进")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack {
                    TextField("微信 / QQ / 邮箱 / GitHub ID", text: $contact)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isProcessing)

                    if !contact.isEmpty {
                        Button {
                            contact = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(F50Theme.controlBackground(for: colorScheme))
                )
            }

            // 详细描述 (必填)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("详细问题描述", systemImage: "pencil.and.outline")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("(必填)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(F50Theme.blue)

                    Spacer()

                    let count = userNotes.trimmingCharacters(in: .whitespacesAndNewlines).count
                    Text(count >= 4 ? "\(count) 字" : "\(count)/4 字")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(count >= 4 ? F50Theme.green : .secondary)
                }

                ZStack(alignment: .topLeading) {
                    if userNotes.isEmpty {
                        Text(selectedCategory.placeholderHint)
                            .font(.system(size: 13.5))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $userNotes)
                        .font(.system(size: 13.5))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 100)
                        .disabled(isProcessing)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(F50Theme.controlBackground(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    userNotes.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
                                        ? F50Theme.blue.opacity(0.3)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(F50Theme.cardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(F50Theme.cardBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private var screenshotCardiOS: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("问题截图", systemImage: "photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text("选填，自动压缩上限 220 KB")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text("已选择 1 张截图")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(String(format: "压缩后大小: %.1f KB", attachedImageSizeKB))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text("更换")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(F50Theme.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(F50Theme.blue.opacity(0.12))
                            )
                    }

                    Button {
                        withAnimation {
                            attachedImage = nil
                            attachedImageBase64 = nil
                            attachedImageSizeKB = 0.0
                            selectedPhotoItem = nil
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(F50Theme.red)
                            .padding(8)
                            .background(
                                Circle().fill(F50Theme.red.opacity(0.1))
                            )
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(F50Theme.controlBackground(for: colorScheme))
                )
            } else {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 16))
                        Text("从相册选择截图")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(F50Theme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(F50Theme.blue.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .foregroundColor(F50Theme.blue.opacity(0.3))
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Text("截图会随反馈原样上传，请勿包含密码、短信正文或其他敏感信息。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(F50Theme.cardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(F50Theme.cardBorder(for: colorScheme), lineWidth: 1)
                )
        )
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

                    Text(fetcher.isDemoMode
                        ? "本次演示仅在本机完成，未发送任何数据。"
                        : "开发者已收到您的脱敏接口诊断快照，将尽快跟进适配与修复。非常感谢您的支持！")
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(F50Theme.blue.opacity(0.12))
                            )
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
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(F50Theme.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(F50Theme.green.opacity(0.3), lineWidth: 1)
                        )
                )
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
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(F50Theme.blue.opacity(0.08))
                    )
                }

                // 主发送按钮
                routerLoginDiagnosticButton

                Button {
                    startProbeAndSubmit()
                } label: {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(isProcessing ? "正在抓取并提交..." : "一键抓取并发送反馈")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isProcessing
                                    ? F50Theme.blue.opacity(0.6)
                                    : F50Theme.blue
                            )
                            .shadow(color: F50Theme.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                    )
                }
                .buttonStyle(.plain)
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
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(F50Theme.orange.opacity(0.1))
                    )
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
                Text(routerLoginSessionCookie == nil ? "登录原厂后台后增强诊断（可选）" : "已获取网页登录会话，将用于增强诊断")
            }
            .font(.system(size: 12.5, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .disabled(isProcessing || routerLoginURL == nil)
    }

    private var diagnosticPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本地诊断报告与脱敏快照", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let rep = report {
                    Button {
                        copyReportToClipboard(rep)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                            Text("复制报告")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(F50Theme.blue)
                    }
                }
            }

            if let rep = report {
                DisclosureGroup(
                    isExpanded: $showDetails,
                    content: {
                        ScrollView {
                            Text(rep.toMarkdown())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 180)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(F50Theme.controlBackground(for: colorScheme))
                        )
                        .padding(.top, 6)
                    },
                    label: {
                        Text("展开查看脱敏 Markdown 数据 (\(rep.endpoints.count) 个接口探测)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                )
            } else {
                Text("提交反馈时将自动对网关接口进行探测并生成诊断报告。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(F50Theme.cardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(F50Theme.cardBorder(for: colorScheme), lineWidth: 1)
                )
        )
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("反馈类型")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedCategory) {
                            ForEach(FeedbackCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.iconName)
                                    .tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

                    // 2. 表单信息输入
                    VStack(alignment: .leading, spacing: 8) {
                        // 设备型号 (必填)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("设备品牌与型号 (必填)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                if !deviceModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(F50Theme.green)
                                }
                            }
                            TextField("例如：中兴 F50 / F30 Pro / 华为 5G CPE / 展锐 MiFi", text: $deviceModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .disabled(isProcessing)
                        }

                        // 联系方式
                        VStack(alignment: .leading, spacing: 4) {
                            Text("您的联系方式 (选填)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            TextField("微信 / QQ / 邮箱，方便开发者沟通跟进", text: $contact)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .disabled(isProcessing)
                        }

                        // 详细描述 (必填)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("详细问题描述 (必填)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                let count = userNotes.trimmingCharacters(in: .whitespacesAndNewlines).count
                                Text(count >= 4 ? "\(count) 字" : "\(count)/4 字")
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
                                Text(selectedCategory.placeholderHint)
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

                        Text("截图会随反馈原样上传，请勿包含密码、短信正文或其他敏感信息。")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
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

                            Text(fetcher.isDemoMode
                                ? "本次演示仅在本机完成，未发送任何数据。"
                                : "开发者已收到您的反馈及脱敏诊断数据并将跟进处理，感谢支持！")
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
                                routerLoginSessionCookie == nil ? "登录原厂后台后增强诊断（可选）" : "已获取网页登录会话，将用于增强诊断",
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

                    // 诊断报告与备份
                    if let rep = report {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("本地诊断结果")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button("复制诊断报告") {
                                    copyReportToClipboard(rep)
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.plain)
                                .foregroundColor(F50Theme.blue)
                            }

                            DisclosureGroup("预览脱敏诊断数据", isExpanded: $showDetails) {
                                TextEditor(text: .constant(rep.toMarkdown()))
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(height: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.2))
                                    )
                            }
                            .font(.system(size: 11))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
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
                self.report = reportResult
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

    private func copyReportToClipboard(_ report: DeviceDiagnosticReport) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report.toMarkdown(), forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = report.toMarkdown()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopiedToast = false
            }
        }
        #endif
        statusFeedbackMessage = "诊断报告已复制到剪贴板！"
    }
}

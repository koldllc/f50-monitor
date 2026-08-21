#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#elseif os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#endif
import SwiftUI
import UniformTypeIdentifiers

public struct DeviceFeedbackView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onClose: () -> Void

    @State private var selectedCategory: FeedbackCategory = .deviceAdaptation
    @State private var deviceModel: String = ""
    @State private var contact: String = ""
    @State private var userNotes: String = ""
    @State private var attachedImage: PlatformImage? = nil
    @State private var attachedImageBase64: String? = nil

    @State private var isProcessing: Bool = false
    @State private var probeProgress: Double = 0.0
    @State private var probeStatusText: String = ""
    @State private var report: DeviceDiagnosticReport? = nil
    @State private var showDetails: Bool = false
    @State private var submitSuccess: Bool = false
    @State private var statusFeedbackMessage: String? = nil
    @State private var createdIssueURL: String? = nil

    private let webhookURL = URL(string: "https://f50-feedback-api.kelvsze.workers.dev")!

    public init(fetcher: F50Fetcher, onClose: @escaping () -> Void) {
        self.fetcher = fetcher
        self.onClose = onClose
    }

    public var body: some View {
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
                        // 设备型号
                        VStack(alignment: .leading, spacing: 4) {
                            Text("设备品牌与型号 (选填)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
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

                        // 详细描述
                        VStack(alignment: .leading, spacing: 4) {
                            Text("详细问题描述 (必填)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

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

                    // 3. 问题截图附加 (macOS 支持选择文件)
                    #if os(macOS)
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

                                Text("已添加 1 张截图")
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary)

                                Spacer()

                                Button {
                                    attachedImage = nil
                                    attachedImageBase64 = nil
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
                    #endif

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
                        // 成功反馈卡片
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(F50Theme.green)
                                    .font(.system(size: 14))
                                Text("反馈发送成功！")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(F50Theme.green)
                            }

                            Text("开发者已收到您的反馈及脱敏诊断数据并将跟进处理，感谢支持！")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            if let issueUrl = createdIssueURL {
                                HStack(spacing: 4) {
                                    Text("GitHub Issue:")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(issueUrl)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(F50Theme.blue)
                                        .lineLimit(1)
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
                        // 主发送按钮
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
        .padding(12)
        .frame(minWidth: 420, minHeight: 460)
    }

    // MARK: - Actions

    private func selectImageFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "选择问题截图"
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
                processAndAttachImage(image)
            }
        }
        #endif
    }

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
        #elseif os(iOS)
        var jpegData = image.jpegData(compressionQuality: 0.6)
        if let data = jpegData, data.count > maxScreenshotBytes {
            jpegData = image.jpegData(compressionQuality: 0.35)
        }
        guard let jpegData, jpegData.count <= maxScreenshotBytes else {
            statusFeedbackMessage = "截图过大（上限 220 KB），请裁剪后重试。"
            return
        }
        self.attachedImage = image
        self.attachedImageBase64 = jpegData.base64EncodedString()
        #endif
    }

    private func startProbeAndSubmit() {
        let trimmedNotes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNotes.count >= 4 else {
            statusFeedbackMessage = "请在「详细问题描述」中至少输入 4 个字符以提供复现说明。"
            return
        }

        isProcessing = true
        probeProgress = 0.0
        probeStatusText = "正在收集运行状态与接口诊断..."
        statusFeedbackMessage = nil
        submitSuccess = false
        createdIssueURL = nil

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
                sessionCookie: fetcher.currentSessionCookie,
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
                let (success, msg) = try await DeviceDiagnosticProbe.shared.submitReportRemote(
                    report: reportResult,
                    webhookURL: webhookURL
                )
                await MainActor.run {
                    self.isProcessing = false
                    if success {
                        self.submitSuccess = true
                        if msg.contains("Issue: "), let urlPart = msg.components(separatedBy: "Issue: ").last {
                            self.createdIssueURL = urlPart.trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                        }
                    } else {
                        self.statusFeedbackMessage = "提交失败: \(msg)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.statusFeedbackMessage = "网络连接失败: \(error.localizedDescription)"
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
        #endif
        statusFeedbackMessage = "诊断报告已复制到剪贴板！"
    }
}

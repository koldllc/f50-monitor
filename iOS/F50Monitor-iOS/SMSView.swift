import SwiftUI
import F50Core

/// iOS 短信列表 + 写短信
struct SMSView: View {
    @ObservedObject var fetcher: F50Fetcher
    @State private var isComposing = false
    @State private var copiedNotice: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if fetcher.isFetchingSMS && fetcher.smsMessages.isEmpty {
                    ProgressView("正在读取短信…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = fetcher.smsErrorMessage, fetcher.smsMessages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(F50Theme.orange)
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") { fetcher.fetchSMSMessages() }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if fetcher.smsMessages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 36))
                            .foregroundColor(F50Theme.gray)
                        Text("暂无短信记录")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button("下拉或点击刷新") { fetcher.fetchSMSMessages() }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(fetcher.smsMessages) { message in
                            messageRow(message)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await fetcher.fetchSMSMessagesAsync()
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("短信")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            isComposing = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.body)
                                .foregroundColor(F50Theme.blue)
                        }
                        Button {
                            fetcher.fetchSMSMessages()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                                .foregroundColor(F50Theme.blue)
                        }
                        .disabled(fetcher.isFetchingSMS)
                    }
                }
            }
            .sheet(isPresented: $isComposing) {
                ComposeSheet(fetcher: fetcher)
            }
            .overlay(alignment: .bottom) {
                if let notice = copiedNotice {
                    Text(notice)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.78)))
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { copiedNotice = nil }
                            }
                        }
                }
            }
        }
        .onAppear {
            if fetcher.smsMessages.isEmpty {
                fetcher.fetchSMSMessages()
            }
        }
    }

    private func messageRow(_ message: F50SMSMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(message.didFailToSend ? F50Theme.red.opacity(0.12) : (message.isOutgoing ? F50Theme.blue.opacity(0.12) : F50Theme.green.opacity(0.12)))
                        .frame(width: 26, height: 26)
                    Image(systemName: message.isOutgoing ? "arrow.up.right" : "arrow.down.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(message.didFailToSend ? F50Theme.red : (message.isOutgoing ? F50Theme.blue : F50Theme.green))
                }

                Text(message.number.isEmpty ? "未知号码" : message.number)
                    .font(.system(size: 15, weight: message.isUnread ? .bold : .semibold, design: .rounded))
                    .foregroundColor(.primary)

                if message.isUnread {
                    Text("未读")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(F50Theme.blue.opacity(0.15)))
                        .foregroundColor(F50Theme.blue)
                }

                Spacer()
                Text(message.dateText)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Text(message.content.isEmpty ? "（空短信）" : message.content)
                .font(.subheadline)
                .textSelection(.enabled)
                .foregroundColor(message.isUnread ? .primary : .secondary)
                .lineSpacing(2)

            // 识别验证码并提示一键复制
            if let code = extractVerificationCode(from: message.content) {
                Button {
                    UIPasteboard.general.string = code
                    withAnimation { copiedNotice = "验证码 \(code) 已复制" }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2.bold())
                        Text("复制验证码: \(code)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(F50Theme.blue.opacity(0.1)))
                    .foregroundColor(F50Theme.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .contextMenu {
            if let code = extractVerificationCode(from: message.content) {
                Button {
                    UIPasteboard.general.string = code
                    withAnimation { copiedNotice = "验证码 \(code) 已复制" }
                } label: {
                    Label("复制验证码 (\(code))", systemImage: "doc.on.doc")
                }
            }
            Button {
                UIPasteboard.general.string = message.content
                withAnimation { copiedNotice = "短信内容已复制" }
            } label: {
                Label("复制完整短信", systemImage: "doc.on.clipboard")
            }
            if !message.number.isEmpty {
                Button {
                    UIPasteboard.general.string = message.number
                    withAnimation { copiedNotice = "号码已复制" }
                } label: {
                    Label("复制发送号码", systemImage: "phone")
                }
            }
        }
    }

    /// 提取短信中的 4-6 位数验证码
    private func extractVerificationCode(from text: String) -> String? {
        let pattern = #"(?<!\d)\d{4,6}(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
}

/// 写短信 Sheet
private struct ComposeSheet: View {
    @ObservedObject var fetcher: F50Fetcher
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var content = ""
    @State private var hasRequestedSend = false

    private var canSend: Bool {
        !number.trimmingCharacters(in: .whitespaces).isEmpty
            && !content.trimmingCharacters(in: .whitespaces).isEmpty
            && !fetcher.isSendingSMS
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("接收号码") {
                    TextField("例如 13800138000", text: $number)
                        .keyboardType(.phonePad)
                }
                Section("短信内容") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                }
                if let error = fetcher.smsSendErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("写短信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(fetcher.isSendingSMS)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        hasRequestedSend = true
                        fetcher.sendSMSMessage(to: number, content: content)
                    } label: {
                        if fetcher.isSendingSMS {
                            ProgressView()
                        } else {
                            Text("发送")
                        }
                    }
                    .disabled(!canSend)
                }
            }
            .interactiveDismissDisabled(fetcher.isSendingSMS)
            .onChange(of: fetcher.smsSendSuccess) { success in
                if success, hasRequestedSend {
                    dismiss()
                    fetcher.fetchSMSMessages()
                }
            }
        }
    }
}

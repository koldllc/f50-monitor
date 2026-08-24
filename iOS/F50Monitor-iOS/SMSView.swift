import SwiftUI
import F50Core

/// iOS 短信列表 + 写短信
struct SMSView: View {
    @ObservedObject var fetcher: F50Fetcher
    @State private var isComposing = false
    @State private var copiedNotice: String? = nil
    @State private var conversationPath: [String] = []

    private struct Conversation: Identifiable {
        let number: String
        let messages: [F50SMSMessage]
        var id: String { number }
        var latest: F50SMSMessage { messages[0] }
        var hasUnread: Bool { messages.contains(where: { $0.isUnread }) }
    }

    private var conversations: [Conversation] {
        var grouped: [String: [F50SMSMessage]] = [:]
        var order: [String] = []
        for message in fetcher.smsMessages {
            let number = message.number.trimmingCharacters(in: .whitespacesAndNewlines)
            if grouped[number] == nil { order.append(number) }
            grouped[number, default: []].append(message)
        }
        return order.compactMap { number in
            grouped[number].map { Conversation(number: number, messages: $0) }
        }
    }

    var body: some View {
        NavigationStack(path: $conversationPath) {
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

                        HStack(spacing: 10) {
                            Button("重试") { fetcher.fetchSMSMessages() }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.bordered)

                            if !fetcher.isDemoMode {
                                Button("开启演示模式") {
                                    fetcher.isDemoMode = true
                                }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if fetcher.smsMessages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 38))
                            .foregroundColor(F50Theme.gray.opacity(0.7))
                        Text("暂无短信记录")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !fetcher.isDemoMode {
                            Button("开启演示模式体验短信功能") {
                                fetcher.isDemoMode = true
                            }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if fetcher.isDemoMode {
                            Section {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(F50Theme.blue)
                                    Text("演示模式：展示模拟短信与验证码识别")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        ForEach(conversations) { conversation in
                            Button {
                                conversationPath.append(conversation.number)
                            } label: {
                                conversationRow(conversation)
                            }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .leading) {
                                    if conversation.hasUnread {
                                        Button {
                                            fetcher.markSMSAsRead(ids: conversation.messages.filter(\.isUnread).map(\.id))
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        } label: {
                                            Label("已读", systemImage: "envelope.open.fill")
                                        }
                                        .tint(.blue)
                                    }
                                }
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
                if fetcher.smsMessages.contains(where: { $0.isUnread }) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            fetcher.markAllSMSAsRead()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Label("全部已读", systemImage: "checkmark.circle")
                                .font(.subheadline)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        fetcher.fetchSMSMessages()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .disabled(fetcher.isFetchingSMS)
                    .help("刷新短信")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    isComposing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(Color.blue)
                                .shadow(color: Color.blue.opacity(0.32), radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .sheet(isPresented: $isComposing) {
                ComposeSheet(fetcher: fetcher)
            }
            .navigationDestination(for: String.self) { number in
                if let conversation = conversations.first(where: { $0.number == number }) {
                    conversationView(conversation)
                }
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
            fetcher.startSMSAutoRefresh()
        }
        .onDisappear {
            fetcher.stopSMSAutoRefresh()
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: conversation.hasUnread ? "message.fill" : "message")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(conversation.hasUnread ? F50Theme.blue : .secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill((conversation.hasUnread ? F50Theme.blue : Color.secondary).opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.number.isEmpty ? "未知号码" : conversation.number)
                        .font(.system(size: 15, weight: conversation.hasUnread ? .bold : .semibold, design: .rounded))
                    if conversation.hasUnread {
                        Text("未读")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(F50Theme.blue.opacity(0.15)))
                            .foregroundColor(F50Theme.blue)
                    }
                    Spacer()
                    Text(conversation.latest.dateText)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Text(conversation.latest.content.isEmpty ? "（空短信）" : conversation.latest.content)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func conversationView(_ conversation: Conversation) -> some View {
        List(conversation.messages.reversed()) { message in
            messageRow(message)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(conversation.number.isEmpty ? "未知号码" : conversation.number)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func messageRow(_ message: F50SMSMessage) -> some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 48) }

            VStack(alignment: .leading, spacing: 8) {
                Text(message.content.isEmpty ? "（空短信）" : message.content)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .foregroundColor(message.isOutgoing ? .white : .primary)
                    .lineSpacing(2)

                // 识别验证码并提示一键复制
                if let code = extractVerificationCode(from: message.content) {
                    Button {
                        UIPasteboard.general.string = code
                        withAnimation { copiedNotice = "验证码 \(code) 已复制" }
                        fetcher.markSMSAsRead(ids: [message.id])
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
                        .background(Capsule().fill(message.isOutgoing ? Color.white.opacity(0.2) : F50Theme.blue.opacity(0.1)))
                        .foregroundColor(message.isOutgoing ? .white : F50Theme.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

                HStack(spacing: 5) {
                    if message.didFailToSend {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(message.isOutgoing ? .white : F50Theme.red)
                    }
                    Text(message.dateText)
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundColor(message.isOutgoing ? Color.white.opacity(0.75) : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(message.didFailToSend ? F50Theme.red : (message.isOutgoing ? F50Theme.blue : Color(.secondarySystemGroupedBackground)))
            )

            if !message.isOutgoing { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if message.isUnread {
                fetcher.markSMSAsRead(ids: [message.id])
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .contextMenu {
            if message.isUnread {
                Button {
                    fetcher.markSMSAsRead(ids: [message.id])
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Label("标为已读", systemImage: "envelope.open")
                }
            }
            if let code = extractVerificationCode(from: message.content) {
                Button {
                    UIPasteboard.general.string = code
                    withAnimation { copiedNotice = "验证码 \(code) 已复制" }
                    fetcher.markSMSAsRead(ids: [message.id])
                } label: {
                    Label("复制验证码 (\(code))", systemImage: "doc.on.doc")
                }
            }
            Button {
                UIPasteboard.general.string = message.content
                withAnimation { copiedNotice = "短信内容已复制" }
                fetcher.markSMSAsRead(ids: [message.id])
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

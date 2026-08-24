import SwiftUI
import F50Core

struct SMSListView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onClose: () -> Void
    @State private var isComposing = false
    @State private var selectedConversationNumber: String?

    var body: some View {
        Group {
            if isComposing {
                ComposeSMSView(
                    fetcher: fetcher,
                    onClose: { isComposing = false },
                    onSent: {
                        isComposing = false
                        fetcher.fetchSMSMessages()
                    }
                )
            } else if let selectedConversationNumber,
                      let conversation = groupedMessages.first(where: { $0.number == selectedConversationNumber }) {
                conversationDetail(conversation)
            } else {
                smsList
            }
        }
    }

    private var smsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onClose) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(F50Theme.blue)

                Spacer()

                Text("短信")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer()

                if fetcher.smsMessages.contains(where: { $0.isUnread }) {
                    Button(action: { fetcher.markAllSMSAsRead() }) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(F50Theme.blue)
                    .help("全部标为已读")
                }

                Button(action: { isComposing = true }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("写短信")

                Button(action: { fetcher.fetchSMSMessages() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(fetcher.isFetchingSMS)
                .help("刷新短信")
            }

            Divider()

            Group {
                if fetcher.isFetchingSMS && fetcher.smsMessages.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("正在读取短信…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = fetcher.smsErrorMessage, fetcher.smsMessages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(F50Theme.orange)
                        Text(error)
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                        Button("重试") { fetcher.fetchSMSMessages() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else if fetcher.smsMessages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("暂无短信记录")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(groupedMessages, id: \.number) { group in
                                Button {
                                    selectedConversationNumber = group.number
                                } label: {
                                    conversationRow(group)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 420)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear { fetcher.startSMSAutoRefresh() }
        .onDisappear { fetcher.stopSMSAutoRefresh() }
    }

    private var groupedMessages: [(number: String, messages: [F50SMSMessage])] {
        var groups: [(number: String, messages: [F50SMSMessage])] = []
        for message in fetcher.smsMessages {
            let number = message.number.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = groups.firstIndex(where: { $0.number == number }) {
                groups[index].messages.append(message)
            } else {
                groups.append((number, [message]))
            }
        }
        return groups
    }

    private func messageGroup(_ group: (number: String, messages: [F50SMSMessage])) -> some View {
        let hasUnread = group.messages.contains(where: { $0.isUnread })

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "phone")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(F50Theme.blue)
                Text(group.number.isEmpty ? "未知号码" : group.number)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if hasUnread {
                    Text("未读")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(F50Theme.blue.opacity(0.15)))
                        .foregroundColor(F50Theme.blue)
                }
                Spacer()
                Text("\(group.messages.count) 条")
                    .font(.system(size: 9, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            }

            ForEach(group.messages) { message in
                messageRow(message)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hasUnread ? F50Theme.blue.opacity(0.08) : Color.primary.opacity(0.04))
        )
    }

    private func conversationRow(_ group: (number: String, messages: [F50SMSMessage])) -> some View {
        let latest = group.messages[0]
        let hasUnread = group.messages.contains(where: { $0.isUnread })

        return HStack(spacing: 9) {
            Image(systemName: hasUnread ? "message.fill" : "message")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(hasUnread ? F50Theme.blue : .secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill((hasUnread ? F50Theme.blue : Color.secondary).opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(group.number.isEmpty ? "未知号码" : group.number)
                        .font(.system(size: 12, weight: hasUnread ? .bold : .semibold, design: .rounded))
                    if hasUnread {
                        Text("未读")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(F50Theme.blue)
                    }
                    Spacer()
                    Text(latest.dateText)
                        .font(.system(size: 9, design: .rounded).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Text(latest.content.isEmpty ? "（空短信）" : latest.content)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hasUnread ? F50Theme.blue.opacity(0.08) : Color.primary.opacity(0.04)))
    }

    private func conversationDetail(_ group: (number: String, messages: [F50SMSMessage])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    selectedConversationNumber = nil
                } label: {
                    Label("短信", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(F50Theme.blue)

                Spacer()
                Text(group.number.isEmpty ? "未知号码" : group.number)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(group.messages.reversed()) { message in
                        messageRow(message)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380, height: 480)
    }

    private func messageRow(_ message: F50SMSMessage) -> some View {
        let alignment: HorizontalAlignment = message.isOutgoing ? .trailing : .leading

        return HStack {
            if message.isOutgoing { Spacer(minLength: 44) }

            VStack(alignment: alignment, spacing: 4) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.content.isEmpty ? "（空短信）" : message.content)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .foregroundColor(message.isOutgoing ? .white : .primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let code = extractVerificationCode(from: message.content) {
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(code, forType: .string)
                            fetcher.markSMSAsRead(ids: [message.id])
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 10))
                                Text("复制验证码: \(code)")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            }
                            .foregroundColor(message.isOutgoing ? .white : F50Theme.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(message.isOutgoing ? Color.white.opacity(0.2) : F50Theme.blue.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(message.didFailToSend ? F50Theme.red : (message.isOutgoing ? F50Theme.blue : Color.primary.opacity(message.isUnread ? 0.08 : 0.04)))
                )

                HStack(spacing: 4) {
                    if message.didFailToSend {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    Text(message.dateText)
                        .font(.system(size: 9, design: .rounded).monospacedDigit())
                }
                .foregroundColor(message.didFailToSend ? F50Theme.red : .secondary)
            }

            if !message.isOutgoing { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if message.isUnread {
                fetcher.markSMSAsRead(ids: [message.id])
            }
        }
        .contextMenu {
            if message.isUnread {
                Button {
                    fetcher.markSMSAsRead(ids: [message.id])
                } label: {
                    Label("标为已读", systemImage: "envelope.open")
                }
            }
            if let code = extractVerificationCode(from: message.content) {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                    fetcher.markSMSAsRead(ids: [message.id])
                } label: {
                    Label("复制验证码 (\(code))", systemImage: "doc.on.doc")
                }
            }
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(message.content, forType: .string)
                fetcher.markSMSAsRead(ids: [message.id])
            } label: {
                Label("复制完整短信", systemImage: "doc.on.clipboard")
            }
            if !message.number.isEmpty {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(message.number, forType: .string)
                } label: {
                    Label("复制发送号码", systemImage: "phone")
                }
            }
        }
    }

    private func extractVerificationCode(from text: String) -> String? {
        let pattern = #"(?<!\d)(\d{4,6})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let matchedString = nsText.substring(with: match.range)
            if matchedString.count >= 4 && matchedString.count <= 6 {
                return matchedString
            }
        }
        return nil
    }
}

import SwiftUI
import F50Core

struct SMSListView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onClose: () -> Void
    @State private var isComposing = false

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
                            ForEach(fetcher.smsMessages) { message in
                                messageRow(message)
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

    private func messageRow(_ message: F50SMSMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: message.isOutgoing ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(message.didFailToSend ? F50Theme.red : (message.isOutgoing ? F50Theme.blue : F50Theme.green))
                Text(message.number.isEmpty ? "未知号码" : message.number)
                    .font(.system(size: 12, weight: message.isUnread ? .bold : .semibold, design: .rounded))
                if message.isUnread {
                    Text("未读")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(F50Theme.blue.opacity(0.15)))
                        .foregroundColor(F50Theme.blue)
                }
                Spacer()
                Text(message.dateText)
                    .font(.system(size: 9, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Text(message.content.isEmpty ? "（空短信）" : message.content)
                .font(.system(size: 12))
                .textSelection(.enabled)
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
                    .foregroundColor(F50Theme.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(F50Theme.blue.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(message.isUnread ? F50Theme.blue.opacity(0.08) : Color.primary.opacity(0.04))
        )
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

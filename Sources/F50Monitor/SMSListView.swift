import SwiftUI

struct SMSListView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onClose) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)

                Spacer()

                Text("短信")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Button(action: fetcher.fetchSMSMessages) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
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
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                        Button("重试", action: fetcher.fetchSMSMessages)
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else if fetcher.smsMessages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("暂无短信")
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
        .onAppear(perform: fetcher.fetchSMSMessages)
    }

    private func messageRow(_ message: F50SMSMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: message.isOutgoing ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(message.didFailToSend ? .red : (message.isOutgoing ? .blue : .green))
                Text(message.number.isEmpty ? "未知号码" : message.number)
                    .font(.system(size: 12, weight: message.isUnread ? .bold : .semibold))
                if message.isUnread {
                    Text("未读")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                }
                Spacer()
                Text(message.dateText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Text(message.content.isEmpty ? "（空短信）" : message.content)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(message.isUnread ? Color.blue.opacity(0.10) : Color.primary.opacity(0.04))
        )
    }
}

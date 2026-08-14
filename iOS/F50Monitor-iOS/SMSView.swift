import SwiftUI
import F50Core

/// iOS 短信列表 + 写短信
struct SMSView: View {
    @ObservedObject var fetcher: F50Fetcher
    @State private var isComposing = false

    var body: some View {
        NavigationStack {
            Group {
                if fetcher.isFetchingSMS && fetcher.smsMessages.isEmpty {
                    ProgressView("正在读取短信…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = fetcher.smsErrorMessage, fetcher.smsMessages.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                        Button("重试") { fetcher.fetchSMSMessages() }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if fetcher.smsMessages.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "envelope.open")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无短信")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(fetcher.smsMessages) { message in
                        messageRow(message)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("短信")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            isComposing = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        Button {
                            fetcher.fetchSMSMessages()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(fetcher.isFetchingSMS)
                    }
                }
            }
            .sheet(isPresented: $isComposing) {
                ComposeSheet(fetcher: fetcher)
            }
        }
        .onAppear {
            if fetcher.smsMessages.isEmpty {
                fetcher.fetchSMSMessages()
            }
        }
    }

    private func messageRow(_ message: F50SMSMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: message.isOutgoing ? "arrow.up.right" : "arrow.down.left")
                    .font(.caption.bold())
                    .foregroundColor(message.didFailToSend ? .red : (message.isOutgoing ? .blue : .green))
                Text(message.number.isEmpty ? "未知号码" : message.number)
                    .font(.subheadline.weight(message.isUnread ? .bold : .semibold))
                if message.isUnread {
                    Text("未读")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                        .foregroundColor(.blue)
                }
                Spacer()
                Text(message.dateText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(message.content.isEmpty ? "（空短信）" : message.content)
                .font(.subheadline)
                .textSelection(.enabled)
                .foregroundColor(message.isUnread ? .primary : .secondary)
        }
        .padding(.vertical, 4)
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

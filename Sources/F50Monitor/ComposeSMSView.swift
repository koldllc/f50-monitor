import SwiftUI
import F50Core

/// 写短信视图：输入号码与内容，通过 UFI-TOOLS 发送
struct ComposeSMSView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onClose: () -> Void
    var onSent: () -> Void

    @State private var number = ""
    @State private var content = ""
    @State private var hasRequestedSend = false

    private var canSend: Bool {
        !number.trimmingCharacters(in: .whitespaces).isEmpty
            && !content.trimmingCharacters(in: .whitespaces).isEmpty
            && !fetcher.isSendingSMS
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onClose) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                .disabled(fetcher.isSendingSMS)

                Spacer()

                Text("写短信")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Color.clear
                    .frame(width: 48, height: 1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("接收号码")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField("例如 13800138000", text: $number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(fetcher.isSendingSMS)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("短信内容")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 13))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .disabled(fetcher.isSendingSMS)
            }

            if let error = fetcher.smsSendErrorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }

            HStack {
                Spacer()
                Button {
                    hasRequestedSend = true
                    fetcher.sendSMSMessage(to: number, content: content)
                } label: {
                    HStack(spacing: 4) {
                        if fetcher.isSendingSMS {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(fetcher.isSendingSMS ? "发送中…" : "发送")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 120)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canSend)
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: fetcher.smsSendSuccess) { success in
            // 发送成功：返回列表并刷新，展示最新短信
            if success, hasRequestedSend {
                onSent()
            }
        }
    }
}

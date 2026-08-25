import SwiftUI
import F50Core

struct F50PopoverView: View {
    @ObservedObject var fetcher: F50Fetcher
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var screenMirroringManager: ScreenMirroringManager
    var onOpenFileShare: () -> Void
    @State private var isShowingSettings = false
    @State private var isShowingSMS = false
    @State private var isShowingFeedback = false

    var body: some View {
        Group {
            if isShowingSMS {
                SMSListView(fetcher: fetcher) {
                    isShowingSMS = false
                }
            } else if isShowingFeedback {
                DeviceFeedbackView(fetcher: fetcher) {
                    isShowingFeedback = false
                }
            } else if isShowingSettings {
                SettingsView(
                    fetcher: fetcher,
                    updateManager: updateManager,
                    screenMirroringManager: screenMirroringManager,
                    onOpenFileShare: onOpenFileShare,
                    onOpenFeedback: {
                        isShowingSettings = false
                        isShowingFeedback = true
                    },
                    onOpenSMS: {
                        isShowingSettings = false
                        isShowingSMS = true
                    },
                    onClose: {
                        isShowingSettings = false
                    }
                )
            } else {
                F50PanelView(
                    fetcher: fetcher,
                    updateManager: updateManager,
                    screenMirroringManager: screenMirroringManager,
                    onOpenSettings: { isShowingSettings = true },
                    onOpenFileShare: onOpenFileShare,
                    onOpenSMS: { isShowingSMS = true },
                    onOpenFeedback: { isShowingFeedback = true }
                )
            }
        }

        .frame(width: 376)
        .fixedSize(horizontal: false, vertical: true)
    }
}

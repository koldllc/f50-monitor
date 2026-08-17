import SwiftUI
import F50Core

struct F50PopoverView: View {
    @ObservedObject var fetcher: F50Fetcher
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var screenMirroringManager: ScreenMirroringManager
    @State private var isShowingSettings = false
    @State private var isShowingSMS = false

    var body: some View {
        Group {
            if isShowingSMS {
                SMSListView(fetcher: fetcher) {
                    isShowingSMS = false
                }
            } else if isShowingSettings {
                SettingsView(
                    fetcher: fetcher,
                    updateManager: updateManager,
                    screenMirroringManager: screenMirroringManager
                ) {
                    isShowingSettings = false
                }
            } else {
                F50PanelView(
                    fetcher: fetcher,
                    updateManager: updateManager,
                    screenMirroringManager: screenMirroringManager,
                    onOpenSettings: { isShowingSettings = true },
                    onOpenSMS: { isShowingSMS = true }
                )
            }
        }

        .frame(width: 376)
        .fixedSize(horizontal: false, vertical: true)
    }
}

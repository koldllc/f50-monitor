import SwiftUI

struct F50PopoverView: View {
    @ObservedObject var fetcher: F50Fetcher
    @ObservedObject var updateManager: UpdateManager
    @State private var isShowingSettings = false
    @State private var isShowingSMS = false

    var body: some View {
        Group {
            if isShowingSMS {
                SMSListView(fetcher: fetcher) {
                    isShowingSMS = false
                }
            } else if isShowingSettings {
                SettingsView(fetcher: fetcher, updateManager: updateManager) {
                    isShowingSettings = false
                }
            } else {
                F50PanelView(
                    fetcher: fetcher,
                    updateManager: updateManager,
                    onOpenSettings: { isShowingSettings = true },
                    onOpenSMS: { isShowingSMS = true }
                )
            }
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

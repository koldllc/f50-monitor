import SwiftUI

struct F50PopoverView: View {
    @ObservedObject var fetcher: F50Fetcher
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if isShowingSettings {
                SettingsView(fetcher: fetcher) {
                    isShowingSettings = false
                }
            } else {
                F50PanelView(fetcher: fetcher) {
                    isShowingSettings = true
                }
            }
        }
        .frame(width: 340, height: 450)
    }
}

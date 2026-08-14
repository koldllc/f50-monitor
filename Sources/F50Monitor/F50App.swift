import AppKit
import SwiftUI
import Combine

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var fetcher: F50Fetcher!
    var updateManager: UpdateManager!
    var screenMirroringManager: ScreenMirroringManager!
    private var cancellables = Set<AnyCancellable>()
    private let smsNotificationManager = SMSNotificationManager()
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Menu bar only app, no dock icon
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        fetcher = F50Fetcher()
        updateManager = UpdateManager()
        screenMirroringManager = ScreenMirroringManager()
        
        // 1. Setup Popover
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        
        let hostingController = NSHostingController(
            rootView: F50PopoverView(
                fetcher: fetcher,
                updateManager: updateManager,
                screenMirroringManager: screenMirroringManager
            )
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        
        // 2. Setup Menu Bar StatusItem with monospaced font
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.alignment = .center
            let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            button.image = NSImage(
                systemSymbolName: "antenna.radiowaves.left.and.right",
                accessibilityDescription: "F50 Monitor"
            )?.withSymbolConfiguration(symbolConfiguration)
            button.imagePosition = .imageLeading
            button.title = "F50 Monitor"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        
        // 3. Observe Status & Settings Changes to Update Menu Bar Text
        Publishers.CombineLatest(fetcher.$status, fetcher.$displayMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status, mode in
                Task<Void, Never> { @MainActor in
                    guard let self else { return }
                    self.updateMenuBarText(status: status, mode: mode)
                }
            }
            .store(in: &cancellables)

        fetcher.$status
            .compactMap { status in
                status.isOnline ? status.smsUnreadCount : nil
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unreadCount in
                Task<Void, Never> { @MainActor in
                    guard let self else { return }
                    self.smsNotificationManager.updateUnreadCount(unreadCount)
                }
            }
            .store(in: &cancellables)

        smsNotificationManager.requestAuthorizationIfNeeded()
        updateManager.checkForUpdates()
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Refresh data on opening popover
            fetcher.fetchData()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    private func updateMenuBarText(status: F50Status, mode: MenuBarDisplayMode) {
        guard let button = statusItem.button else { return }
        
        guard status.isOnline else {
            statusItem.length = 50
            button.title = "离线"
            return
        }
        
        switch mode {
        case .iconOnly:
            statusItem.length = 26
            button.title = ""
            
        case .speeds:
            statusItem.length = 175
            let dlStr = F50Status.formatSpeedFixedWidth(status.dlSpeed)
            let ulStr = F50Status.formatSpeedFixedWidth(status.ulSpeed)
            button.title = "⬇\(dlStr) ⬆\(ulStr)"
            
        case .cpuMem:
            statusItem.length = 120
            if status.cpuUsage > 0 || status.memUsage > 0 {
                button.title = String(format: "C:%2.0f%% M:%2.0f%%", status.cpuUsage, status.memUsage)
            } else {
                let dlStr = F50Status.formatSpeedFixedWidth(status.dlSpeed)
                button.title = "⬇\(dlStr)"
            }
            
        case .temperature:
            statusItem.length = 85
            if status.temperature > 0 {
                button.title = String(format: "%4.1f℃", status.temperature)
            } else {
                button.title = status.networkType
            }
            
        case .devices:
            statusItem.length = 70
            button.title = "\(status.connectedDevices)台"
            
        case .full:
            statusItem.length = 170
            let dlStr = F50Status.formatSpeedFixedWidth(status.dlSpeed)
            let type = status.networkType.replacingOccurrences(of: "5G ", with: "")
            if status.temperature > 0 {
                button.title = String(format: "%@ ⬇%@ %.0f℃", type, dlStr, status.temperature)
            } else {
                button.title = String(format: "%@ ⬇%@", type, dlStr)
            }
        }
    }
}

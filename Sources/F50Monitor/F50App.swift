import AppKit
import F50Core
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
        statusItem.length = NSStatusItem.variableLength

        guard status.isOnline else {
            if mode == .iconOnly {
                button.title = ""
            } else {
                button.title = "离线"
            }
            button.toolTip = "F50 Monitor (未连接后台)"
            return
        }

        switch mode {
        case .iconOnly:
            button.title = ""
            button.toolTip = "F50 Monitor (\(status.networkType) · \(status.carrier))\n下载: \(F50Status.formatSpeed(status.dlSpeed))  上传: \(F50Status.formatSpeed(status.ulSpeed))"

        case .speeds:
            button.title = "⬇ \(F50Status.formatSpeed(status.dlSpeed))  ⬆ \(F50Status.formatSpeed(status.ulSpeed))"
            button.toolTip = "F50 Monitor: 实时速率"

        case .cpuMem:
            if status.cpuUsage > 0 || status.memUsage > 0 {
                button.title = String(format: "CPU %.0f%%  内存 %.0f%%", status.cpuUsage, status.memUsage)
            } else {
                button.title = "⬇ \(F50Status.formatSpeed(status.dlSpeed))"
            }
            button.toolTip = "F50 Monitor: 硬件负载"

        case .temperature:
            if status.temperature > 0 {
                button.title = String(format: "%.1f℃", status.temperature)
            } else {
                button.title = status.networkType
            }
            button.toolTip = "F50 Monitor: 芯片温度"

        case .devices:
            button.title = "Wi-Fi: \(status.connectedDevices) 台"
            button.toolTip = "F50 Monitor: Wi-Fi 连接设备数 (\(status.connectedDevices) 台)"

        case .traffic:
            let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
            if status.trafficLimit > 0 {
                button.title = "\(F50Status.formatBytes(packageUsed)) / \(F50Status.formatBytes(status.trafficLimit))"
            } else {
                button.title = "已用 \(F50Status.formatBytes(packageUsed))"
            }
            button.toolTip = "F50 Monitor: 套餐流量 (已用: \(F50Status.formatBytes(packageUsed)) / 总量: \(status.trafficLimit > 0 ? F50Status.formatBytes(status.trafficLimit) : "不限"))"
        }
    }
}

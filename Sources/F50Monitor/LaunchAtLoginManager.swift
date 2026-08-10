import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        isUpdating = true
        errorMessage = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = enabled ? "无法开启自启动：\(error.localizedDescription)" : "无法关闭自启动：\(error.localizedDescription)"
        }

        refresh()
        isUpdating = false
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App 与 Widget 之间的数据共享（通过 App Group 的共享 UserDefaults）。
/// macOS 端无 App Group 时 UserDefaults(suiteName:) 返回 nil，读写均为空操作，安全。
public enum F50WidgetDataStore {
    public static let appGroupID = "group.com.f50.monitor"
    private static let statusKey = "widget.status"

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    public static func saveStatus(_ status: F50Status) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        sharedDefaults?.set(data, forKey: statusKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    public static func loadStatus() -> F50Status? {
        guard let data = sharedDefaults?.data(forKey: statusKey) else { return nil }
        return try? JSONDecoder().decode(F50Status.self, from: data)
    }

    public static func clear() {
        sharedDefaults?.removeObject(forKey: statusKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

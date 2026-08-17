import Foundation
import SwiftUI

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Codable {
    case iconOnly = "仅图标"
    case speeds = "图标 + 速率"
    case traffic = "图标 + 套餐用量"
    case cpuMem = "图标 + CPU/内存"
    case temperature = "图标 + 温度"
    case devices = "图标 + Wi-Fi 设备数"

    public var id: String { rawValue }
}

public struct F50Status: Equatable, Codable {
    public var isOnline: Bool = false
    public var errorMessage: String? = nil
    public var ufiAuthFailed: Bool = false  // True if port 2333 returned 401

    public var networkType: String = "5G SA" // e.g. "5G SA", "5G NSA", "4G LTE"
    public var signalBar: Int = 0           // 0 to 5
    public var rsrp: String = "N/A"         // e.g. "-85 dBm"
    public var rsrq: String = "N/A"         // e.g. "-7 dB"
    public var snr: String = "N/A"          // e.g. "8 dB"
    public var carrier: String = "未知"     // e.g. "中国移动"
    public var currentBands: String = ""   // e.g. "B3 + n78"
    public var pppStatus: String = "未连接"

    // QCI & Subscription Rates (Empty if not fetched from modem)
    public var qci: String = ""
    public var qosDl: String = ""
    public var qosUl: String = ""

    public var dlSpeed: Double = 0.0        // Bytes per sec
    public var ulSpeed: Double = 0.0        // Bytes per sec
    public var dlHistory: [Double] = []
    public var ulHistory: [Double] = []

    public var connectedDevices: Int = 0
    public var smsUnreadCount: Int = 0
    public var cpuUsage: Double = 0.0       // 0 - 100%
    public var memUsage: Double = 0.0       // 0 - 100%
    public var temperature: Double = 0.0    // ℃

    public var batteryValue: Int = -1       // -1 means no battery or N/A
    public var isCharging: Bool = false

    public var monthlyRx: UInt64 = 0
    public var monthlyTx: UInt64 = 0
    public var realtimeRx: UInt64 = 0
    public var realtimeTx: UInt64 = 0
    public var dailyRx: UInt64 = 0
    public var dailyTx: UInt64 = 0
    public var trackedDaily: UInt64 = 0
    public var trafficLimit: UInt64 = 0
    // 套餐账单周期累计（Router 80 端口 monthly_rx_bytes/monthly_tx_bytes，如 138.67GB）
    // 与 UFI 的“本月已用”不同：此字段用于“套餐已用”与进度条
    public var packageRx: UInt64 = 0
    public var packageTx: UInt64 = 0
    public var packageTotal: UInt64 { packageRx + packageTx }
    // UFI cellularUsage 按日期范围精确查询（与 F50 后台“当日/本月”同口径）
    public var ufiDailyUsage: UInt64 = 0
    public var ufiMonthlyUsage: UInt64 = 0
    // 0 表示未知/尚未检测到；此时不显示重置天数
    public var trafficResetDay: Int = 0

    public var daysUntilReset: Int? {
        guard (1...31).contains(trafficResetDay) else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentDay = calendar.component(.day, from: today)
        let resetDayToUse = trafficResetDay
        
        let targetDate: Date
        if currentDay <= resetDayToUse {
            var components = calendar.dateComponents([.year, .month], from: today)
            let range = calendar.range(of: .day, in: .month, for: today) ?? 1..<31
            components.day = min(resetDayToUse, range.count)
            targetDate = calendar.date(from: components) ?? today
        } else {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) else { return 0 }
            var components = calendar.dateComponents([.year, .month], from: nextMonth)
            let range = calendar.range(of: .day, in: .month, for: nextMonth) ?? 1..<31
            components.day = min(resetDayToUse, range.count)
            targetDate = calendar.date(from: components) ?? today
        }
        
        let diff = calendar.dateComponents([.day], from: today, to: targetDate)
        return max(0, diff.day ?? 0)
    }

    public var monthlyOffsetBytes: Int64 = 0
    public var dailyOffsetBytes: Int64 = 0

    public var monthlyTotal: UInt64 {
        let raw = monthlyRx + monthlyTx
        if monthlyOffsetBytes != 0 {
            // Int64(clamping:) 防止设备上报的极端大值(如 UInt64.max 脏数据)导致崩溃
            let adjusted = Int64(clamping: raw) + monthlyOffsetBytes
            return UInt64(max(0, adjusted))
        }
        return raw
    }

    public var sessionTotal: UInt64 { realtimeRx + realtimeTx }

    public var dailyTotal: UInt64 {
        let nativeDaily = dailyRx + dailyTx
        let raw = nativeDaily > 0 ? nativeDaily : max(trackedDaily, sessionTotal)
        if dailyOffsetBytes != 0 {
            let adjusted = Int64(clamping: raw) + dailyOffsetBytes
            return UInt64(max(0, adjusted))
        }
        return raw
    }

    public var trafficUsageRatio: Double {
        guard trafficLimit > 0 else { return 0 }
        // 优先用套餐账单周期累计（Router），无则回退 UFI 月度值
        let used = packageTotal > 0 ? packageTotal : monthlyTotal
        return min(1.0, max(0.0, Double(used) / Double(trafficLimit)))
    }

    public var trafficUsageColor: Color {
        guard trafficLimit > 0 else { return F50Theme.cyan }
        let ratio = trafficUsageRatio
        if ratio >= 0.9 {
            return F50Theme.red
        } else if ratio >= 0.75 {
            return F50Theme.orange
        } else {
            return F50Theme.cyan
        }
    }

    public var lastUpdated: Date = Date()

    public init() {}

    mutating func mergeHardwareMetrics(from payload: [String: Any]) {
        if let value = payload["cpu_utility"] ?? payload["cpu_usage"] {
            let parsed = F50ResponseParser.parseDouble(value)
            if parsed > 0 { cpuUsage = parsed }
        }
        if let value = payload["mem_utility"] ?? payload["mem_usage"] {
            let parsed = F50ResponseParser.parseDouble(value)
            if parsed > 0 { memUsage = parsed }
        }
        if let value = payload["ic_temp"] ?? payload["soc_temp"] ?? payload["modem_temp"] ?? payload["cpu_temp"] {
            let parsed = F50ResponseParser.parseDouble(value)
            if parsed > 0 { temperature = parsed }
        }
    }

    mutating func clearHardwareMetrics() {
        cpuUsage = 0
        memUsage = 0
        temperature = 0
    }

    // Helper to extract double value from string
    private func parseVal(_ str: String) -> Double? {
        let clean = str.replacingOccurrences(of: "dBm", with: "")
                       .replacingOccurrences(of: "dB", with: "")
                       .trimmingCharacters(in: .whitespaces)
        return Double(clean)
    }

    // RSRP Quality (Excellent >= -85, Good >= -95, Fair >= -105, Poor < -105)
    public var rsrpQuality: (label: String, color: Color, ratio: Double) {
        guard let val = parseVal(rsrp) else { return ("-", .secondary, 0.0) }
        if val >= -85 {
            return ("极佳", F50Theme.green, 1.0)
        } else if val >= -95 {
            return ("良好", F50Theme.blue, 0.75)
        } else if val >= -105 {
            return ("一般", F50Theme.orange, 0.50)
        } else {
            return ("较差", F50Theme.red, 0.25)
        }
    }

    // SINR Quality (Excellent >= 20, Good >= 13, Fair >= 3, Poor < 3)
    public var snrQuality: (label: String, color: Color, ratio: Double) {
        guard let val = parseVal(snr) else { return ("-", .secondary, 0.0) }
        if val >= 20 {
            return ("极佳", F50Theme.green, 1.0)
        } else if val >= 13 {
            return ("良好", F50Theme.blue, 0.75)
        } else if val >= 3 {
            return ("一般", F50Theme.orange, 0.50)
        } else {
            return ("较差", F50Theme.red, 0.25)
        }
    }

    // RSRQ Quality (Excellent >= -10, Good >= -15, Fair >= -20, Poor < -20)
    public var rsrqQuality: (label: String, color: Color, ratio: Double) {
        guard let val = parseVal(rsrq) else { return ("-", .secondary, 0.0) }
        if val >= -10 {
            return ("极佳", F50Theme.green, 1.0)
        } else if val >= -15 {
            return ("良好", F50Theme.blue, 0.75)
        } else if val >= -20 {
            return ("一般", F50Theme.orange, 0.50)
        } else {
            return ("较差", F50Theme.red, 0.25)
        }
    }

    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024.0)
        } else if bytesPerSec < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f GB/s", bytesPerSec / (1024.0 * 1024.0 * 1024.0))
        }
    }

    public static func formatSpeedFixedWidth(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%3.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%4.1f KB/s", bytesPerSec / 1024.0)
        } else if bytesPerSec < 1024 * 1024 * 1024 {
            return String(format: "%4.1f MB/s", bytesPerSec / (1024.0 * 1024.0))
        } else {
            return String(format: "%4.2f GB/s", bytesPerSec / (1024.0 * 1024.0 * 1024.0))
        }
    }

    public static func formatBytes(_ bytes: UInt64) -> String {
        let dBytes = Double(bytes)
        if dBytes < 1024 {
            return "\(bytes) B"
        } else if dBytes < 1024 * 1024 {
            return String(format: "%.1f KB", dBytes / 1024.0)
        } else if dBytes < 1024 * 1024 * 1024 {
            return String(format: "%.2f MB", dBytes / (1024.0 * 1024.0))
        } else if dBytes < 1024 * 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", dBytes / (1024.0 * 1024.0 * 1024.0))
        } else {
            return String(format: "%.2f TB", dBytes / (1024.0 * 1024.0 * 1024.0 * 1024.0))
        }
    }

    public var signalIconName: String {
        guard isOnline else { return "wifi.slash" }
        return signalBar > 0 ? "cellularbars" : "antenna.radiowaves.left.and.right"
    }

    public var tempColor: Color {
        if temperature <= 0 {
            return .secondary
        } else if temperature < 45 {
            return F50Theme.green
        } else if temperature < 60 {
            return F50Theme.orange
        } else {
            return F50Theme.red
        }
    }

    public var cpuColor: Color {
        if cpuUsage <= 0 {
            return .secondary
        } else if cpuUsage < 50 {
            return F50Theme.green
        } else if cpuUsage < 80 {
            return F50Theme.orange
        } else {
            return F50Theme.red
        }
    }

    public var memColor: Color {
        if memUsage <= 0 {
            return .secondary
        } else if memUsage < 60 {
            return F50Theme.green
        } else if memUsage < 85 {
            return F50Theme.orange
        } else {
            return F50Theme.red
        }
    }

    public mutating func recordSpeed(dl: Double, ul: Double) {
        dlHistory.append(dl)
        if dlHistory.count > 16 {
            dlHistory.removeFirst(dlHistory.count - 16)
        }
        ulHistory.append(ul)
        if ulHistory.count > 16 {
            ulHistory.removeFirst(ulHistory.count - 16)
        }
    }
}

/// 高级低饱和度调色盘与全局主题规范
public enum F50Theme {
    public static let green = Color(red: 0.18, green: 0.68, blue: 0.45)    // 翡翠绿
    public static let blue = Color(red: 0.22, green: 0.50, blue: 0.92)     // 霁蓝
    public static let orange = Color(red: 0.94, green: 0.58, blue: 0.20)   // 琥珀金
    public static let red = Color(red: 0.88, green: 0.32, blue: 0.32)      // 绯红
    public static let purple = Color(red: 0.54, green: 0.46, blue: 0.84)   // 鸢尾紫
    public static let cyan = Color(red: 0.20, green: 0.66, blue: 0.70)     // 烟青蓝
    public static let gray = Color(red: 0.55, green: 0.58, blue: 0.62)     // 岩灰

    public static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.115, green: 0.145, blue: 0.185)
            : Color.white
    }

    public static func panelBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.10, blue: 0.135)
            : Color(red: 0.945, green: 0.955, blue: 0.97)
    }

    public static func cardBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }

    public static func controlBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.04)
    }

    public static func controlHover(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.08)
    }
}

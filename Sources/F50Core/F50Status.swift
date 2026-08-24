import Foundation
import SwiftUI

public enum SignalNoiseMetricKind: String, Codable, Sendable {
    case sinr = "SINR"
    case snr = "SNR"
    case unknown = "SINR / SNR"
}

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
    // 可选字段保证旧版 App Group JSON 仍可解码；来源键用于区分真实 SINR 与 SNR。
    public var rsrpSource: String? = nil
    public var rsrqSource: String? = nil
    public var snrSource: String? = nil
    public var snrMetricKind: SignalNoiseMetricKind? = nil
    public var carrier: String = "未知"     // e.g. "中国移动"
    public var currentBands: String = ""   // e.g. "B3 + n78"
    public var pci: String? = nil
    public var cellId: String? = nil
    public var tac: String? = nil
    public var cellIdentitySource: String? = nil
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
        if currentDay < resetDayToUse {
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

    func requiresQosRefresh(comparedTo previous: F50Status) -> Bool {
        if isOnline && !previous.isOnline { return true }
        if pppStatus == "已连接" && previous.pppStatus != "已连接" { return true }
        if carrier != previous.carrier && carrier != "未知" { return true }
        if networkType != previous.networkType && !networkType.isEmpty { return true }
        if currentBands != previous.currentBands && !currentBands.isEmpty { return true }
        return false
    }

    mutating func mergeHardwareMetrics(from payload: [String: Any]) {
        if let value = payload["cpu_utility"] ?? payload["cpu_usage"] ?? payload["cpu_percent"] ?? payload["cpu_rate"] ?? payload["cpu"] ?? payload["cpu_load"] {
            let parsed = F50ResponseParser.parseDouble(value)
            if parsed > 0 { cpuUsage = min(100.0, max(0.0, parsed)) }
        }
        if let value = payload["mem_utility"] ?? payload["mem_usage"] ?? payload["mem_percent"] ?? payload["memory_rate"] ?? payload["memory"] ?? payload["mem_used_percent"] {
            let parsed = F50ResponseParser.parseDouble(value)
            if parsed > 0 { memUsage = min(100.0, max(0.0, parsed)) }
        }
        let temperatureKeys = ["cpu_temp", "temperature", "temp", "ic_temp", "soc_temp", "modem_temp", "internal_temperature", "chip_temp", "device_temp"]
        if let value = temperatureKeys.lazy.compactMap({ payload[$0] }).first {
            var parsed = F50ResponseParser.parseDouble(value)
            if parsed > 1_000 { parsed /= 1_000.0 }
            if parsed > 0 && parsed < 130 { temperature = parsed }
        }
        if let value = payload["qci"] ?? payload["qci_val"] ?? payload["qos_qci"] {
            let str = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !str.isEmpty && str != "0" && str != "null" {
                qci = str
            }
        }
        if let dl = payload["qos_dl"] ?? payload["qos_downlink"] {
            let str = String(describing: dl).trimmingCharacters(in: .whitespacesAndNewlines)
            if !str.isEmpty && str != "0" && str != "null" { qosDl = str }
        }
        if let ul = payload["qos_ul"] ?? payload["qos_uplink"] {
            let str = String(describing: ul).trimmingCharacters(in: .whitespacesAndNewlines)
            if !str.isEmpty && str != "0" && str != "null" { qosUl = str }
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

    // MARK: - 审核与演示模式模拟数据 (Demo Mode Mock Data)
    public static var mock: F50Status {
        mockStatus(tick: 0)
    }

    public static func mockStatus(tick: Int = 0) -> F50Status {
        var s = F50Status()
        s.isOnline = true
        s.errorMessage = nil
        s.ufiAuthFailed = false

        s.networkType = "5G SA"
        s.signalBar = 4
        s.rsrp = "-82 dBm"
        s.rsrq = "-7 dB"
        s.snr = "19 dB"
        s.rsrpSource = "nr_rsrp"
        s.rsrqSource = "nr_rsrq"
        s.snrSource = "nr_sinr"
        s.snrMetricKind = .sinr
        s.carrier = "中国移动"
        s.currentBands = "B3 + n78"
        s.pci = "321"
        s.cellId = "0x01A2B3C4"
        s.tac = "1024"
        s.cellIdentitySource = "Demo"
        s.pppStatus = "已连接"

        s.qci = "9 (默认互联网承载)"
        s.qosDl = "1000 Mbps"
        s.qosUl = "150 Mbps"

        // 模拟自然呼吸波动的上下行速率
        let baseDl = 48.5 * 1024.0 * 1024.0
        let baseUl = 6.2 * 1024.0 * 1024.0
        let wave = sin(Double(tick) * 0.5) * 6.0 * 1024.0 * 1024.0
        s.dlSpeed = max(12.0 * 1024.0 * 1024.0, baseDl + wave)
        s.ulSpeed = max(1.5 * 1024.0 * 1024.0, baseUl + (wave * 0.18))

        s.dlHistory = [
            18.2 * 1024 * 1024,
            24.5 * 1024 * 1024,
            31.0 * 1024 * 1024,
            42.8 * 1024 * 1024,
            55.3 * 1024 * 1024,
            49.1 * 1024 * 1024,
            46.7 * 1024 * 1024,
            s.dlSpeed
        ]
        s.ulHistory = [
            2.1 * 1024 * 1024,
            3.4 * 1024 * 1024,
            4.2 * 1024 * 1024,
            5.8 * 1024 * 1024,
            6.5 * 1024 * 1024,
            5.9 * 1024 * 1024,
            6.1 * 1024 * 1024,
            s.ulSpeed
        ]

        s.connectedDevices = 3
        s.smsUnreadCount = 1
        s.cpuUsage = max(15.0, min(85.0, 26.5 + (sin(Double(tick) * 0.35) * 4.0)))
        s.memUsage = 41.8
        s.temperature = max(30.0, min(65.0, 39.2 + (sin(Double(tick) * 0.2) * 0.8)))

        s.packageRx = 38_654_705_664 // ~36.0 GB
        s.packageTx = 4_294_967_296  // ~4.0 GB
        s.trafficLimit = 107_374_182_400 // 100 GB
        s.trafficResetDay = 1
        s.batteryValue = -1

        return s
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

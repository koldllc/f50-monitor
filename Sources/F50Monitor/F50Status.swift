import Foundation
import SwiftUI

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Codable {
    case iconOnly = "仅图标"
    case speeds = "图标 + 速率"
    case cpuMem = "图标 + CPU/内存"
    case temperature = "图标 + 温度"
    case devices = "图标 + 设备数"
    case full = "完整显示"
    
    public var id: String { rawValue }
}

public struct F50Status: Equatable {
    public var isOnline: Bool = false
    public var errorMessage: String? = nil
    public var ufiAuthFailed: Bool = false  // True if port 2333 returned 401
    
    public var networkType: String = "5G SA" // e.g. "5G SA", "5G NSA", "4G LTE"
    public var signalBar: Int = 0           // 0 to 5
    public var rsrp: String = "N/A"         // e.g. "-85 dBm"
    public var rsrq: String = "N/A"         // e.g. "-7 dB"
    public var snr: String = "N/A"          // e.g. "8 dB"
    public var carrier: String = "未知"     // e.g. "中国移动"
    public var pppStatus: String = "未连接"
    
    // QCI & Subscription Rates (Empty if not fetched from modem)
    public var qci: String = ""
    public var qosDl: String = ""
    public var qosUl: String = ""
    
    public var dlSpeed: Double = 0.0        // Bytes per sec
    public var ulSpeed: Double = 0.0        // Bytes per sec
    
    public var connectedDevices: Int = 0
    public var cpuUsage: Double = 0.0       // 0 - 100%
    public var memUsage: Double = 0.0       // 0 - 100%
    public var temperature: Double = 0.0    // ℃
    
    public var batteryValue: Int = -1       // -1 means no battery or N/A
    public var isCharging: Bool = false
    
    public var monthlyRx: UInt64 = 0
    public var monthlyTx: UInt64 = 0
    
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
            return ("极佳", .green, 1.0)
        } else if val >= -95 {
            return ("良好", .blue, 0.75)
        } else if val >= -105 {
            return ("一般", .orange, 0.50)
        } else {
            return ("较差", .red, 0.25)
        }
    }
    
    // SINR Quality (Excellent >= 20, Good >= 13, Fair >= 3, Poor < 3)
    public var snrQuality: (label: String, color: Color, ratio: Double) {
        guard let val = parseVal(snr) else { return ("-", .secondary, 0.0) }
        if val >= 20 {
            return ("极佳", .green, 1.0)
        } else if val >= 13 {
            return ("良好", .blue, 0.75)
        } else if val >= 3 {
            return ("一般", .orange, 0.50)
        } else {
            return ("较差", .red, 0.25)
        }
    }
    
    // RSRQ Quality (Excellent >= -10, Good >= -15, Fair >= -20, Poor < -20)
    public var rsrqQuality: (label: String, color: Color, ratio: Double) {
        guard let val = parseVal(rsrq) else { return ("-", .secondary, 0.0) }
        if val >= -10 {
            return ("极佳", .green, 1.0)
        } else if val >= -15 {
            return ("良好", .blue, 0.75)
        } else if val >= -20 {
            return ("一般", .orange, 0.50)
        } else {
            return ("较差", .red, 0.25)
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
        } else {
            return String(format: "%.2f GB", dBytes / (1024.0 * 1024.0 * 1024.0))
        }
    }
    
    public var signalIconName: String {
        guard isOnline else { return "wifi.slash" }
        switch signalBar {
        case 5: return "cellularbars"
        case 4: return "cellularbars"
        case 3: return "cellularbars"
        case 2: return "cellularbars"
        case 1: return "cellularbars"
        default: return "antenna.radiowaves.left.and.right"
        }
    }
    
    public var tempColor: Color {
        if temperature <= 0 {
            return .secondary
        } else if temperature < 45 {
            return .green
        } else if temperature < 60 {
            return .orange
        } else {
            return .red
        }
    }
    
    public var cpuColor: Color {
        if cpuUsage <= 0 {
            return .secondary
        } else if cpuUsage < 50 {
            return .green
        } else if cpuUsage < 80 {
            return .orange
        } else {
            return .red
        }
    }
    
    public var memColor: Color {
        if memUsage <= 0 {
            return .secondary
        } else if memUsage < 60 {
            return .green
        } else if memUsage < 85 {
            return .orange
        } else {
            return .red
        }
    }
}

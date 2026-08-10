import Foundation

struct ParsedQos: Equatable {
    let qci: String
    let downlink: String
    let uplink: String
}

enum F50ResponseParser {
    static func parseQos(_ raw: String) -> ParsedQos? {
        let clean = raw.replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = clean.components(separatedBy: ",")
        guard parts.count >= 8, parts[0].contains("+CGEQOSRDP:") else { return nil }

        let qci = parts[1].trimmingCharacters(in: .whitespaces)
        let dlRaw = parts[6].trimmingCharacters(in: .whitespaces)
        let ulRaw = parts[7].components(separatedBy: .whitespaces).first { !$0.isEmpty } ?? ""
        guard let dlKbps = Double(dlRaw), let ulKbps = Double(ulRaw) else { return nil }

        return ParsedQos(
            qci: qci,
            downlink: formatRate(dlKbps),
            uplink: formatRate(ulKbps)
        )
    }

    static func parsePPPStatus(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "connected" || normalized == "connect" || normalized == "1" {
            return "已连接"
        }
        if normalized == "disconnected" || normalized == "disconnect" || normalized == "0" {
            return "未连接"
        }
        return raw
    }

    static func parseInt(_ value: Any) -> Int {
        if let number = value as? Int { return number }
        if let string = value as? String {
            let clean = string.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            return Int(clean) ?? 0
        }
        return 0
    }

    static func parseDouble(_ value: Any) -> Double {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let string = value as? String {
            let clean = string.replacingOccurrences(of: "℃", with: "")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Double(clean) ?? 0
        }
        return 0
    }

    static func parseUInt64(_ value: Any) -> UInt64 {
        if let number = value as? UInt64 { return number }
        if let number = value as? Int { return UInt64(max(0, number)) }
        if let string = value as? String {
            let clean = string.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            return UInt64(clean) ?? 0
        }
        return 0
    }

    static func parseTrafficLimit(size: Any?, unit: Any?) -> UInt64 {
        guard String(describing: unit ?? "").lowercased() == "data" else { return 0 }

        let parts = String(describing: size ?? "").split(separator: "_", maxSplits: 1)
        guard let value = Double(parts.first ?? ""), value > 0 else { return 0 }
        let multiplier = parts.count == 2 ? (Double(parts[1]) ?? 1) : 1
        let bytes = value * multiplier * 1024 * 1024
        guard bytes.isFinite, bytes > 0, bytes <= Double(UInt64.max) else { return 0 }
        return UInt64(bytes)
    }

    private static func formatRate(_ kbps: Double) -> String {
        kbps >= 1000
            ? String(format: "%.0fMbps", kbps / 1000)
            : String(format: "%.0fKbps", kbps)
    }
}

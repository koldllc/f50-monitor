import Foundation

struct ParsedQos: Equatable {
    let qci: String
    let downlink: String
    let uplink: String
}

enum F50ResponseParser {
    static func normalizeUFIPayload(_ payload: [String: Any]) -> [String: Any] {
        var normalized = payload

        copyFirstValue(in: &normalized, to: "battery_value", from: ["battery", "battery_percent"])
        copyFirstValue(in: &normalized, to: "battery_charging", from: ["is_charging", "charging"])
        copyFirstValue(in: &normalized, to: "wifi_access_sta_num", from: ["station_num", "client_count", "connected_devices"])
        copyFirstValue(in: &normalized, to: "network_provider", from: ["carrier", "operator", "operator_name"])
        copyFirstValue(in: &normalized, to: "network_type", from: ["network_mode", "rat"])
        copyFirstValue(in: &normalized, to: "signalbar", from: ["signal_bar", "signal_level"])
        copyFirstValue(in: &normalized, to: "realtime_rx_thrpt", from: ["download_speed", "rx_speed"])
        copyFirstValue(in: &normalized, to: "realtime_tx_thrpt", from: ["upload_speed", "tx_speed"])

        copyFirstValue(in: &normalized, to: "day_rx_bytes", from: ["daily_rx_bytes", "today_rx_bytes"])
        copyFirstValue(in: &normalized, to: "day_tx_bytes", from: ["daily_tx_bytes", "today_tx_bytes"])
        if normalized["day_rx_bytes"] == nil && normalized["day_tx_bytes"] == nil {
            copyFirstValue(in: &normalized, to: "day_rx_bytes", from: ["daily_data", "day_data"])
        }
        if normalized["monthly_rx_bytes"] == nil && normalized["monthly_tx_bytes"] == nil {
            copyFirstValue(in: &normalized, to: "monthly_rx_bytes", from: ["monthly_data", "month_data"])
        }

        if let temperature = normalized["cpu_temp"] {
            let value = parseDouble(temperature)
            if value > 1_000 {
                normalized["cpu_temp"] = value / 1_000
            }
        }
        return normalized
    }

    private static func copyFirstValue(
        in payload: inout [String: Any],
        to target: String,
        from aliases: [String]
    ) {
        guard payload[target] == nil else { return }
        for alias in aliases {
            if let value = payload[alias] {
                payload[target] = value
                return
            }
        }
    }

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
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let number = value as? UInt64 {
            return number
        }
        if let number = value as? Int {
            return UInt64(max(0, number))
        }
        if let number = value as? Double {
            return number.isFinite && number >= 0 ? UInt64(number) : 0
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
                let hexStr = String(trimmed.dropFirst(2))
                return UInt64(hexStr, radix: 16) ?? 0
            }
            if let uVal = UInt64(trimmed) {
                return uVal
            }
            if let dVal = Double(trimmed), dVal.isFinite && dVal >= 0 {
                return UInt64(dVal)
            }
            let clean = trimmed.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            return UInt64(clean) ?? 0
        }
        return 0
    }

    static func parseCellularUsage(_ json: [String: Any]) -> UInt64? {
        guard let rows = json["usage"] as? [[String: Any]] else { return nil }
        return rows.reduce(0) { total, row in
            total + parseUInt64(row["usage"] ?? 0)
        }
    }

    static func parseTrafficLimit(size: Any?, unit: Any?) -> UInt64 {
        let sizeStr = String(describing: size ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let unitStr = String(describing: unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !sizeStr.isEmpty, sizeStr != "0", sizeStr != "null", sizeStr != "undefined" else { return 0 }

        // 1. Check if size string contains underscore separators e.g. "1536_1", "100_1024" or "500_1"
        let parts = sizeStr.split(separator: "_").compactMap { Double($0) }
        if parts.count >= 2 {
            let value = parts[0]
            guard value > 0 else { return 0 }
            let subMultiplier = parts[1] > 0 ? parts[1] : 1.0
            let bytes = value * subMultiplier * 1024.0 * 1024.0
            if bytes.isFinite && bytes > 0 && bytes <= Double(UInt64.max) {
                return UInt64(bytes)
            }
        }

        // 2. Single numeric size value
        let cleanSize = sizeStr.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()
        guard let numValue = Double(cleanSize), numValue > 0 else { return 0 }

        let multiplier: Double
        if unitStr == "gb" || unitStr == "1" || unitStr == "g" {
            multiplier = 1024.0 * 1024.0 * 1024.0
        } else if unitStr == "mb" || unitStr == "0" || unitStr == "m" {
            multiplier = 1024.0 * 1024.0
        } else if unitStr == "tb" || unitStr == "2" || unitStr == "t" {
            multiplier = 1024.0 * 1024.0 * 1024.0 * 1024.0
        } else if unitStr == "kb" || unitStr == "k" {
            multiplier = 1024.0
        } else if unitStr == "data" || unitStr == "data_volume" || unitStr == "size" {
            multiplier = numValue < 1000 ? 1024.0 * 1024.0 * 1024.0 : 1024.0 * 1024.0
        } else if numValue > 1_000_000_000 {
            multiplier = 1.0
        } else if numValue > 100_000 {
            multiplier = 1024.0
        } else {
            multiplier = 1024.0 * 1024.0 * 1024.0
        }

        let totalBytes = numValue * multiplier
        if totalBytes.isFinite && totalBytes > 0 && totalBytes <= Double(UInt64.max) {
            return UInt64(totalBytes)
        }
        return 0
    }

    static func parseCurrentBands(from payload: [String: Any], networkType: String) -> String {
        let lteBand = firstBand(
            in: payload,
            keys: ["lte_ca_pcell_band", "wan_active_band", "lte_band"],
            prefix: "B"
        )
        let nrBand = firstBand(
            in: payload,
            keys: ["nr5g_action_band", "nr5g_action_nsa_band", "ZCELLINFO_band", "Z5g_CELLINFO_band", "nr_ca_pcell_band"],
            prefix: "n"
        )

        if networkType == "5G NSA" {
            return [lteBand, nrBand].compactMap { $0 }.joined(separator: " + ")
        }
        if networkType.hasPrefix("5G") {
            return nrBand ?? lteBand ?? ""
        }
        return lteBand ?? ""
    }

    private static func firstBand(in payload: [String: Any], keys: [String], prefix: String) -> String? {
        for key in keys {
            guard let value = payload[key] else { continue }
            let raw = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, raw != "0",
                  let range = raw.range(of: #"\d+"#, options: .regularExpression) else { continue }
            return prefix + String(raw[range])
        }
        return nil
    }

    private static func formatRate(_ kbps: Double) -> String {
        kbps >= 1000
            ? String(format: "%.0fMbps", kbps / 1000)
            : String(format: "%.0fKbps", kbps)
    }
}

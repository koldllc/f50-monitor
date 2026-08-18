import Foundation
import CryptoKit

struct ParsedQos: Equatable {
    let qci: String
    let downlink: String
    let uplink: String
}

enum F50ResponseParser {
    static func parseSMSMessages(_ json: [String: Any]) -> [F50SMSMessage]? {
        guard let rows = json["messages"] as? [[String: Any]] else { return nil }

        return rows.compactMap { row in
            let id = stringValue(row["id"])
            guard !id.isEmpty else { return nil }

            let encodedContent = stringValue(row["content"])
            let decodedContent = Data(base64Encoded: encodedContent, options: .ignoreUnknownCharacters)
                .flatMap { String(data: $0, encoding: .utf8) }

            return F50SMSMessage(
                id: id,
                number: stringValue(row["number"]),
                content: decodedContent ?? encodedContent,
                dateText: formatSMSDate(stringValue(row["date"])),
                tag: stringValue(row["tag"])
            )
        }
    }

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
        // 注意：daily_data/monthly_data 是“自某时刻起的累计值”（设备重置后从 0 累计），
        // 不能当作“当日/本月”精确用量；当日/本月由 /api/cellularUsage 按日期区间查询。
        if normalized["monthly_rx_bytes"] == nil && normalized["monthly_tx_bytes"] == nil {
            copyFirstValue(in: &normalized, to: "monthly_rx_bytes", from: ["monthly_data", "month_data"])
        }
        copyFirstValue(in: &normalized, to: "data_volume_clear_date", from: [
            "monthly_clear_date",
            "clear_date",
            "data_volume_clear_day",
            "monthly_clear_day",
            "clear_day",
            "data_volume_reset_day",
            "billing_day",
            "reset_day",
            "monthly_reset_day",
            "traffic_clear_day",
            "traffic_clear_date",
            "billing_date"
        ])

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

    private static func stringValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatSMSDate(_ raw: String) -> String {
        let values = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard values.count >= 6 else { return raw }
        return "\(values[0])-\(values[1])-\(values[2]) \(values[3]):\(values[4]):\(values[5])"
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

    static func extractFirstValidResetDay(from dict: [String: Any]) -> Int {
        // 同时覆盖 ZTE 路由器路径的 *_day 键与 UFI 路径归一化后的 *_date 键
        let candidateKeys = [
            "traffic_clear_date",
            "data_volume_clear_date",
            "monthly_clear_date",
            "clear_date",
            "data_volume_reset_date",
            "billing_date",
            "data_volume_clear_day",
            "monthly_clear_day",
            "clear_day",
            "data_volume_reset_day",
            "billing_day",
            "reset_day",
            "monthly_reset_day",
            "traffic_clear_day"
        ]
        for key in candidateKeys {
            if let val = dict[key] {
                let day = parseResetDayValue(val)
                if day > 0 && day <= 31 {
                    return day
                }
            }
        }
        return 0
    }

    /// 从清零日取值中提取“日”。支持纯数字日（如 "16"）以及完整日期（如
    /// "2026-08-16" / "2026/8/16" / "2026年8月16日"）。
    private static func parseResetDayValue(_ value: Any) -> Int {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return 0 }

            // 若看起来像完整日期，优先按日期解析并取其日分量
            if trimmed.contains("-") || trimmed.contains("/") || trimmed.contains(".") || trimmed.contains("年") {
                let formats = ["yyyy-MM-dd", "yyyy/M/d", "yyyy.M.d", "yyyy年M月d日"]
                for format in formats {
                    let formatter = DateFormatter()
                    formatter.dateFormat = format
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    if let date = formatter.date(from: trimmed) {
                        let day = Calendar.current.component(.day, from: date)
                        if day > 0 && day <= 31 {
                            return day
                        }
                    }
                }
            }
        }
        return parseInt(value)
    }

    /// UFI-TOOLS 设备的请求签名（设备端协议固定，已用真实设备抓包验证）：
    /// HMAC-MD5(data) 拆前后两半，各自对【原始字节】做 SHA-256，拼接后再 SHA-256，
    /// 输出小写 hex。注意：是对原始字节做哈希，不是对 hex 文本。
    static func kanoSign(key: String, data: String) -> String {
        let keyData = Data(key.utf8)
        let msgData = Data(data.utf8)
        let hmac = HMAC<Insecure.MD5>.authenticationCode(for: msgData, using: SymmetricKey(data: keyData))
        let hmacData = Data(hmac)
        let half = hmacData.count / 2
        let sha1 = SHA256.hash(data: hmacData.subdata(in: 0..<half))
        let sha2 = SHA256.hash(data: hmacData.subdata(in: half..<hmacData.count))
        var combined = Data()
        combined.append(contentsOf: sha1)
        combined.append(contentsOf: sha2)
        return SHA256.hash(data: combined).compactMap { String(format: "%02x", $0) }.joined()
    }

    static func parseInt(_ value: Any) -> Int {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let val = Int(trimmed) { return val }
            if let firstNumericPart = string.components(separatedBy: CharacterSet.decimalDigits.inverted).first(where: { !$0.isEmpty }),
               let val = Int(firstNumericPart) {
                return val
            }
        }
        return 0
    }

    static func parseDouble(_ value: Any) -> Double {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let string = value as? String {
            // 先剥 "dBm" 再剥 "dB"，避免把 "dBm" 拆成 "m"
            let clean = string.replacingOccurrences(of: "℃", with: "")
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: "dBm", with: "")
                .replacingOccurrences(of: "dB", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Double(clean) ?? 0
        }
        return 0
    }

    /// 信号指标取值：从候选键中依次取第一个可解析为“非零数值”的值。
    /// - 大小写不敏感（部分固件返回 Nr_snr / nr_snr、5g_rsrp / 5G_rsrp 等变体）
    /// - 跳过 null / "0" / 无效值：设备在 NSA/4G 等状态下会把不适用的字段置为
    ///   null 或 0，若用 `??` 链会因首键命中无效值而短路，真实值永远读不到。
    static func firstValidSignalValue(in dict: [String: Any], keys: [String]) -> Double? {
        var lowercased: [String: Any] = [:]
        for (key, value) in dict {
            lowercased[key.lowercased()] = value
        }
        for key in keys {
            guard let value = lowercased[key.lowercased()] else { continue }
            let num = parseDouble(value)
            if num != 0 { return num }
        }
        return nil
    }

    static func parseUInt64(_ value: Any) -> UInt64 {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        // JSON 数值都是 NSNumber，此分支覆盖纯 Swift UInt64 值（如测试/本地构造）
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

    static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 计算 ZTE / UFI-TOOLS 登录的密码哈希
    /// 公式：SHA256(SHA256(plaintext) + LD).uppercased()
    /// 若 tokenOrPassword 已是 64 位 SHA256 hex，则直接用作第一层哈希，避免二次哈希
    static func calculateLoginPasswordHash(tokenOrPassword: String, ld: String) -> String {
        let trimmed = tokenOrPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSha256Hex = trimmed.count == 64 &&
            trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil
        let pwdHash1 = isSha256Hex ? trimmed.lowercased() : sha256Hex(trimmed).lowercased()
        return sha256Hex(pwdHash1 + ld).uppercased()
    }

    /// 格式化短信时间字符串：yy;MM;dd;HH;mm;ss;+TZ
    static func formatSMSTime(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yy;MM;dd;HH;mm;ss"
        let base = formatter.string(from: date)
        let tzOffsetSeconds = timeZone.secondsFromGMT(for: date)
        let tzOffsetHours = tzOffsetSeconds / 3600
        let tzSign = tzOffsetHours >= 0 ? "+" : "-"
        return "\(base);\(tzSign)\(abs(tzOffsetHours))"
    }

    /// 构造标准 ZTE / UFI-TOOLS 发送短信请求体 (application/x-www-form-urlencoded)
    static func buildSMSRequestBody(
        number: String,
        content: String,
        ad: String? = nil,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let rawNum = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNum = rawNum.filter { $0 != " " && $0 != "-" && $0 != "(" && $0 != ")" }

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")

        let encodedNumber = cleanNum.addingPercentEncoding(withAllowedCharacters: allowed) ?? cleanNum
        let rawSmsTime = formatSMSTime(date: date, timeZone: timeZone)
        let encodedSmsTime = rawSmsTime.addingPercentEncoding(withAllowedCharacters: allowed) ?? rawSmsTime
        let gsmBody = gsmEncode(content)

        var formParts = [
            "isTest=false",
            "goformId=SEND_SMS",
            "notCallback=true",
            "Number=\(encodedNumber)",
            "sms_time=\(encodedSmsTime)",
            "MessageBody=\(gsmBody)",
            "ID=-1",
            "encode_type=UNICODE"
        ]
        if let ad = ad, !ad.isEmpty {
            formParts.append("AD=\(ad)")
        }
        return formParts.joined(separator: "&")
    }

    /// UFI-TOOLS 短信发送的消息体编码：UTF-16BE 的 hex 字符串
    /// （与 UFI 后台 gsmEncode 一致，非 GSM 7-bit）
    static func gsmEncode(_ text: String) -> String {
        var bytes: [UInt8] = []
        for scalar in text.unicodeScalars {
            let cp = scalar.value
            if cp <= 0xFFFF {
                bytes.append(UInt8((cp >> 8) & 0xFF))
                bytes.append(UInt8(cp & 0xFF))
            } else {
                let high = 0xD800 + ((cp - 0x10000) >> 10)
                let low = 0xDC00 + ((cp - 0x10000) & 0x3FF)
                bytes.append(UInt8((high >> 8) & 0xFF))
                bytes.append(UInt8(high & 0xFF))
                bytes.append(UInt8((low >> 8) & 0xFF))
                bytes.append(UInt8(low & 0xFF))
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
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
            // Nr_bands 来自 network_information dump（F50 不返回 nr5g_action_band 等字段）
            keys: ["nr5g_action_band", "nr5g_action_nsa_band", "ZCELLINFO_band", "Z5g_CELLINFO_band", "nr_ca_pcell_band", "Nr_bands"],
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

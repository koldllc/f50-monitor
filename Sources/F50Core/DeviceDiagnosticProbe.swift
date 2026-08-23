import Foundation
import CryptoKit
import Darwin

// MARK: - Feedback Category (反馈类型)

public enum FeedbackCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case deviceAdaptation = "新设备适配"
    case connectionFailure = "无法连接 / 频繁断连"
    case missingData = "数据缺失 / 显示不全"
    case inaccurateData = "数据不准 / 速率或流量偏差"
    case smsIssue = "短信读取 / 发送异常"
    case screenMirroringIssue = "无线投屏 (scrcpy) 异常"
    case featureSuggestion = "功能建议 / 体验优化"
    case appBug = "软件崩溃 / 其他程序 Bug"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .deviceAdaptation: return "plus.circle.fill"
        case .connectionFailure: return "wifi.exclamationmark"
        case .missingData: return "questionmark.circle.fill"
        case .inaccurateData: return "speedometer"
        case .smsIssue: return "envelope.badge.fill"
        case .screenMirroringIssue: return "tv.slash.fill"
        case .featureSuggestion: return "lightbulb.fill"
        case .appBug: return "ladybug.fill"
        }
    }

    public var placeholderHint: String {
        switch self {
        case .deviceAdaptation:
            return "请描述设备型号、品牌及后台管理地址，点击下方按钮将自动抓取接口数据..."
        case .connectionFailure:
            return "请描述无法连接的具体现象（如：一直显示未在线、提示密码错误、IP超时等）..."
        case .missingData:
            return "请描述哪些指标显示为 `--` 或无数据（如：芯片温度、CPU占用、5G频段等）..."
        case .inaccurateData:
            return "请描述与实际/官方后台不一致的数据项（如：套餐流量清零日不准、实时速率偏差等）..."
        case .smsIssue:
            return "请描述短信读取或发送时的具体错误提示或现象..."
        case .screenMirroringIssue:
            return "请描述投屏无法启动、ADB连接超时或黑屏闪退的具体情况..."
        case .featureSuggestion:
            return "欢迎分享您的使用体验、新增功能诉求或界面改进建议..."
        case .appBug:
            return "请描述触发问题的操作步骤、错误提示或异常行为..."
        }
    }
}

// MARK: - Network Environment Helper (局域网与网关环境检测)

public enum NetworkEnvironmentHelper {
    public static func getLocalNetworkInterfaces() -> [String: String] {
        var addresses: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return addresses }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING) && (flags & IFF_LOOPBACK) == 0 {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let name = String(cString: ptr.pointee.ifa_name)
                        let ip = String(cString: hostname)
                        addresses[name] = ip
                    }
                }
            }
        }
        return addresses
    }

    public static func formatNetworkSummary() -> String {
        let interfaces = getLocalNetworkInterfaces()
        if interfaces.isEmpty { return "未检测到活跃局域网接口" }
        return interfaces.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
}

// MARK: - App State Snapshot (当前运行状态快照)

public struct AppStateSnapshot: Codable, Sendable {
    public let isOnline: Bool
    public let networkType: String
    public let carrier: String
    public let currentBands: String
    public let signalBar: Int
    public let rsrp: String
    public let snr: String
    public let rsrq: String
    public let dlSpeed: Double
    public let ulSpeed: Double
    public let cpuUsage: Double
    public let memUsage: Double
    public let temperature: Double
    public let connectedDevices: Int
    public let trafficResetDay: Int
    public let monthlyTotalBytes: UInt64
    public let dailyTotalBytes: UInt64
    public let packageTotalBytes: UInt64
    public let trafficLimitBytes: UInt64
    public let smsUnreadCount: Int
    public let lastErrorMessage: String?
    public let lastSMSErrorMessage: String?
    public let localInterfaces: String
    public let hasAdb: Bool
    public let hasScrcpy: Bool
    public let firmwareVersion: String
    public let activeChannelMode: String
    public let recentLogs: [String]

    public init(
        isOnline: Bool = false,
        networkType: String = "",
        carrier: String = "",
        currentBands: String = "",
        signalBar: Int = 0,
        rsrp: String = "",
        snr: String = "",
        rsrq: String = "",
        dlSpeed: Double = 0,
        ulSpeed: Double = 0,
        cpuUsage: Double = 0,
        memUsage: Double = 0,
        temperature: Double = 0,
        connectedDevices: Int = 0,
        trafficResetDay: Int = 0,
        monthlyTotalBytes: UInt64 = 0,
        dailyTotalBytes: UInt64 = 0,
        packageTotalBytes: UInt64 = 0,
        trafficLimitBytes: UInt64 = 0,
        smsUnreadCount: Int = 0,
        lastErrorMessage: String? = nil,
        lastSMSErrorMessage: String? = nil,
        localInterfaces: String = NetworkEnvironmentHelper.formatNetworkSummary(),
        hasAdb: Bool = false,
        hasScrcpy: Bool = false,
        firmwareVersion: String = "",
        activeChannelMode: String = "80 Router -> 5555 ADB -> 2333 UFI",
        recentLogs: [String] = []
    ) {
        self.isOnline = isOnline
        self.networkType = networkType
        self.carrier = carrier
        self.currentBands = currentBands
        self.signalBar = signalBar
        self.rsrp = rsrp
        self.snr = snr
        self.rsrq = rsrq
        self.dlSpeed = dlSpeed
        self.ulSpeed = ulSpeed
        self.cpuUsage = cpuUsage
        self.memUsage = memUsage
        self.temperature = temperature
        self.connectedDevices = connectedDevices
        self.trafficResetDay = trafficResetDay
        self.monthlyTotalBytes = monthlyTotalBytes
        self.dailyTotalBytes = dailyTotalBytes
        self.packageTotalBytes = packageTotalBytes
        self.trafficLimitBytes = trafficLimitBytes
        self.smsUnreadCount = smsUnreadCount
        self.lastErrorMessage = lastErrorMessage
        self.lastSMSErrorMessage = lastSMSErrorMessage
        self.localInterfaces = localInterfaces
        self.hasAdb = hasAdb
        self.hasScrcpy = hasScrcpy
        self.firmwareVersion = firmwareVersion
        self.activeChannelMode = activeChannelMode
        self.recentLogs = recentLogs
    }
}

// MARK: - Endpoint Probe Definition

public struct EndpointProbeDef: Sendable {
    public let name: String
    public let vendor: String
    public let path: String
    public let method: String
    public let portOverride: Int?
    public let headers: [String: String]

    public init(
        name: String,
        vendor: String,
        path: String,
        method: String = "GET",
        portOverride: Int? = nil,
        headers: [String: String] = [:]
    ) {
        self.name = name
        self.vendor = vendor
        self.path = path
        self.method = method
        self.portOverride = portOverride
        self.headers = headers
    }
}

// MARK: - Endpoint Probe Result

public struct EndpointProbeResult: Codable, Identifiable, Sendable {
    public var id: String { name + url }
    public let name: String
    public let vendor: String
    public let url: String
    public let method: String
    public let statusCode: Int
    public let statusText: String
    public let latencyMs: Int
    public let contentType: String
    public let serverHeader: String
    public let responseSnippet: String
    public let isSuccess: Bool
    public let authUsed: String?

    public init(
        name: String,
        vendor: String,
        url: String,
        method: String,
        statusCode: Int,
        statusText: String,
        latencyMs: Int,
        contentType: String,
        serverHeader: String,
        responseSnippet: String,
        isSuccess: Bool,
        authUsed: String? = nil
    ) {
        self.name = name
        self.vendor = vendor
        self.url = url
        self.method = method
        self.statusCode = statusCode
        self.statusText = statusText
        self.latencyMs = latencyMs
        self.contentType = contentType
        self.serverHeader = serverHeader
        self.responseSnippet = responseSnippet
        self.isSuccess = isSuccess
        self.authUsed = authUsed
    }
}

// MARK: - Device Diagnostic Report (综合反馈与诊断包)

public struct DeviceDiagnosticReport: Codable, Sendable {
    public let id: String
    public let timestamp: String
    public let category: FeedbackCategory
    public let appVersion: String
    public let osVersion: String
    public let deviceModel: String
    public let userNotes: String
    public let contact: String
    public let targetBaseURL: String
    public let appState: AppStateSnapshot?
    public let screenshotBase64: String?
    public let endpoints: [EndpointProbeResult]
    public let discoveredScriptAPIs: [String]?

    public init(
        id: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        category: FeedbackCategory = .deviceAdaptation,
        appVersion: String,
        osVersion: String,
        deviceModel: String,
        userNotes: String,
        contact: String = "",
        targetBaseURL: String,
        appState: AppStateSnapshot? = nil,
        screenshotBase64: String? = nil,
        endpoints: [EndpointProbeResult] = [],
        discoveredScriptAPIs: [String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.userNotes = userNotes
        self.contact = contact
        self.targetBaseURL = targetBaseURL
        self.appState = appState
        self.screenshotBase64 = screenshotBase64
        self.endpoints = endpoints
        self.discoveredScriptAPIs = discoveredScriptAPIs
    }

    public var successfulProbesCount: Int {
        endpoints.filter { $0.isSuccess }.count
    }

    public func toJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }

    public static let maxPayloadBytes = 512 * 1024

    public func toJSONString() -> String {
        guard let data = toJSONData(), let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    public func toMarkdown() -> String {
        var md = ""
        md += "# 📋 [\(category.rawValue)] 问题与诊断报告\n\n"
        md += "- **反馈类型**: `\(category.rawValue)`\n"
        md += "- **诊断编号**: `\(id)`\n"
        md += "- **提交时间**: `\(timestamp)`\n"
        md += "- **目标设备型号**: **\(deviceModel.isEmpty ? "未指定 (待识别)" : deviceModel)**\n"
        if !contact.isEmpty {
            md += "- **联系方式**: `\(contact)`\n"
        }
        md += "- **目标地址**: `\(DiagnosticSanitizer.maskAddress(targetBaseURL))`\n"
        md += "- **客户端环境**: macOS / iOS (\(osVersion)), F50 Monitor v\(appVersion)\n\n"

        md += "## 📝 详细问题描述\n\n"
        md += "\(userNotes.isEmpty ? "（用户未输入详细说明）" : userNotes)\n\n"

        if let state = appState {
            md += "## ⚡ 当前应用状态快照\n\n"
            md += "- **在线状态**: \(state.isOnline ? "🟢 在线" : "🔴 离线")\n"
            md += "- **网络制式 / 运营商**: `\(state.networkType.isEmpty ? "未知" : state.networkType)` / `\(state.carrier.isEmpty ? "未知" : state.carrier)`\n"
            if !state.currentBands.isEmpty {
                md += "- **活跃频段**: `\(state.currentBands)`\n"
            }
            md += "- **信号指标**: RSRP: `\(state.rsrp)` | SNR: `\(state.snr)` | RSRQ: `\(state.rsrq)` (信号格数: \(state.signalBar))\n"
            md += "- **硬件状态**: 温度: `\(state.temperature)℃` | CPU: `\(state.cpuUsage)%` | 内存: `\(state.memUsage)%` | Wi-Fi设备: `\(state.connectedDevices)`\n"
            if !state.firmwareVersion.isEmpty {
                md += "- **设备固件版本**: `\(state.firmwareVersion)`\n"
            }
            md += "- **数据采集降级链**: `\(state.activeChannelMode)`\n"
            md += "- **本机网络接口**: `\(state.localInterfaces)`\n"
            if let lastErr = state.lastErrorMessage, !lastErr.isEmpty {
                md += "- **最近错误**: `\(lastErr)`\n"
            }
            if let smsErr = state.lastSMSErrorMessage, !smsErr.isEmpty {
                md += "- **短信模块错误**: `\(smsErr)`\n"
            }
            if !state.recentLogs.isEmpty {
                md += "\n<details>\n<summary><b>📜 运行与降级日志流水 (最近 \(state.recentLogs.count) 条)</b></summary>\n\n```text\n"
                md += state.recentLogs.joined(separator: "\n")
                md += "\n```\n</details>\n"
            }
            md += "\n"
        }

        if let discovered = discoveredScriptAPIs, !discovered.isEmpty {
            md += "## 🌐 前端 JS 脚本中发现的候选 API 路径\n\n"
            for api in discovered {
                md += "- `\(api)`\n"
            }
            md += "\n"
        }

        if !endpoints.isEmpty {
            md += "## 📊 接口探测概览 (共 \(endpoints.count) 个接口，\(successfulProbesCount) 个有效响应)\n\n"
            md += "| 接口名称 | 厂商/分类 | 状态 | 耗时 | 鉴权模式 | 返回类型 |\n"
            md += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"

            for ep in endpoints {
                let statusBadge = ep.isSuccess ? "✅ \(ep.statusCode)" : (ep.statusCode > 0 ? "⚠️ \(ep.statusCode)" : "❌ 异常")
                let authTag = ep.authUsed != nil ? "`\(ep.authUsed!)`" : "-"
                md += "| \(ep.name) | \(ep.vendor) | \(statusBadge) | \(ep.latencyMs)ms | \(authTag) | `\(ep.contentType.isEmpty ? "-" : ep.contentType)` |\n"
            }

            md += "\n## 🔍 有效接口返回明细 (已自动脱敏)\n\n"

            let respondingEndpoints = endpoints.filter { $0.statusCode > 0 && !$0.responseSnippet.isEmpty }
            for ep in respondingEndpoints {
                md += "<details>\n"
                md += "<summary><b>\(ep.isSuccess ? "🟢" : "🟡") [\(ep.vendor)] \(ep.name)</b> — <code>\(ep.statusText)</code></summary>\n\n"
                md += "- **URL**: `\(DiagnosticSanitizer.maskAddress(ep.url))`\n"
                if !ep.serverHeader.isEmpty {
                    md += "- **Server**: `\(ep.serverHeader)`\n"
                }
                if !ep.contentType.isEmpty {
                    md += "- **Content-Type**: `\(ep.contentType)`\n"
                }
                if let auth = ep.authUsed {
                    md += "- **Auth Mode**: `\(auth)`\n"
                }
                md += "\n```\(ep.contentType.contains("json") ? "json" : (ep.contentType.contains("html") || ep.contentType.contains("xml") ? "html" : "text"))\n"
                md += ep.responseSnippet
                md += "\n```\n\n"
                md += "</details>\n\n"
            }
        }

        md += "---\n"
        md += "> 🔒 *注：本报告已在本地客户端完成隐私脱敏（已自动剔除/遮蔽密码、密钥、完整 IMEI/IMSI/MAC 及短信内容）。*\n"
        return md
    }
}

// MARK: - Diagnostic Sanitizer (脱敏处理器)

public enum DiagnosticSanitizer {
    public static func maskAddress(_ address: String) -> String {
        guard let url = URL(string: address.contains("://") ? address : "http://" + address) else {
            return address
        }
        let scheme = url.scheme ?? "http"
        let host = url.host ?? ""
        let port = url.port.map { ":\($0)" } ?? ""
        let path = url.path
        let query = url.query.map { "?" + maskQueryString($0) } ?? ""
        return "\(scheme)://\(host)\(port)\(path)\(query)"
    }

    public static func maskQueryString(_ query: String) -> String {
        let items = query.components(separatedBy: "&")
        let masked = items.map { item -> String in
            let parts = item.components(separatedBy: "=")
            guard parts.count == 2 else { return item }
            let key = parts[0]
            let val = parts[1]
            if isSensitiveKey(key) {
                return "\(key)=******"
            }
            return "\(key)=\(val)"
        }
        return masked.joined(separator: "&")
    }

    public static func isSensitiveKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        if lower == "ad" || lower == "rd" { return true }
        let sensitiveWords = [
            "pass", "pwd", "token", "secret", "psk", "wpa_key", "key",
            "credential", "auth", "session", "wa_inner_version_key"
        ]
        return sensitiveWords.contains { lower.contains($0) }
    }

    public static func isIdentifierKey(_ lowerKey: String) -> Bool {
        if lowerKey == "snr" || lowerKey == "rsnr" || lowerKey.hasSuffix("_snr") {
            return false
        }
        if lowerKey.contains("imei") || lowerKey.contains("imsi") || lowerKey.contains("iccid") ||
           lowerKey.contains("phone") || lowerKey.contains("number") || lowerKey.contains("msisdn") {
            return true
        }
        return lowerKey == "sn" || lowerKey.contains("serial")
    }

    public static func sanitizeResponseSnippet(_ text: String, contentType: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            let sanitizedObj = sanitizeJSON(json)
            if let formattedData = try? JSONSerialization.data(withJSONObject: sanitizedObj, options: [.prettyPrinted, .sortedKeys]),
               let formattedStr = String(data: formattedData, encoding: .utf8) {
                return truncateSnippet(formattedStr)
            }
        }

        var sanitized = trimmed

        sanitized = sanitized.replacingOccurrences(
            of: #""(?i)(password|pwd|token|wpa_key|psk|secret|key)"\s*:\s*"[^"]*""#,
            with: "\"$1\": \"******\"",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"\b(\d{4})\d{7}(\d{4})\b"#,
            with: "$1*******$2",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"\b(460\d{2})\d{6}(\d{4})\b"#,
            with: "$1******$2",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"\b([0-9a-fA-F]{2}:[0-9a-fA-F]{2}):(?:[0-9a-fA-F]{2}:){2}([0-9a-fA-F]{2}:[0-9a-fA-F]{2})\b"#,
            with: "$1:**:**:$2",
            options: .regularExpression
        )

        return truncateSnippet(sanitized)
    }

    private static func sanitizeJSON(_ object: Any) -> Any {
        if let dict = object as? [String: Any] {
            var newDict: [String: Any] = [:]
            for (key, value) in dict {
                let lower = key.lowercased()
                if isSensitiveKey(lower) {
                    newDict[key] = "******"
                } else if isIdentifierKey(lower) {
                    let strVal = String(describing: value)
                    newDict[key] = maskIdentifier(strVal)
                } else if lower.contains("mac") || lower.contains("bssid") {
                    let strVal = String(describing: value)
                    newDict[key] = maskMAC(strVal)
                } else if lower == "message" || lower == "content" || lower == "sms" || lower == "sms_content" || lower == "sms_message" {
                    // content/message 可能是嵌套对象或数组；统一占位，避免正文从嵌套层泄漏。
                    newDict[key] = "[已脱敏过滤]"
                } else {
                    newDict[key] = sanitizeJSON(value)
                }
            }
            return newDict
        } else if let array = object as? [Any] {
            return array.map { sanitizeJSON($0) }
        }
        return object
    }

    public static func maskIdentifier(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 8 else { return "******" }
        let prefix = clean.prefix(3)
        let suffix = clean.suffix(4)
        return "\(prefix)****\(suffix)"
    }

    public static func maskPhone(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 7 else { return "******" }
        let prefix = clean.prefix(3)
        let suffix = clean.suffix(4)
        return "\(prefix)****\(suffix)"
    }

    public static func maskMAC(_ raw: String) -> String {
        let parts = raw.split(separator: ":")
        guard parts.count == 6 else { return "**:**:**:**:**:**" }
        return "\(parts[0]):\(parts[1]):**:**:\(parts[4]):\(parts[5])"
    }

    private static func truncateSnippet(_ text: String, maxLength: Int = 3072) -> String {
        if text.count <= maxLength { return text }
        let index = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<index]) + "\n... [截取前 3KB 字符]"
    }
}

// MARK: - Device Diagnostic Probe Engine

public final class DeviceDiagnosticProbe: @unchecked Sendable {
    public static let shared = DeviceDiagnosticProbe()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.5
        config.timeoutIntervalForResource = 6.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config, delegate: F50NetworkDelegate.shared, delegateQueue: nil)
    }()

    // 公网反馈必须走系统默认的严格 TLS 校验；只有局域网设备探测允许自签名证书。
    private let publicSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 20.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    /// 扩充后的全品牌接口探测清单 (涵盖中兴、UFI、华为、展锐、高通、MTK、OPPO、飞猫、蒲公英等)
    public static let defaultProbeDefs: [EndpointProbeDef] = [
        // 1. 基础 Web 页面与登录页
        EndpointProbeDef(name: "Web UI 首页 (/)", vendor: "通用/基础", path: "/"),
        EndpointProbeDef(name: "Web UI 登录页", vendor: "通用/基础", path: "/index.html"),
        EndpointProbeDef(name: "Web UI Home 页", vendor: "通用/基础", path: "/home.html"),
        EndpointProbeDef(name: "Web UI Default 页", vendor: "通用/基础", path: "/default.html"),
        EndpointProbeDef(name: "Web UI Login 页", vendor: "通用/基础", path: "/login.html"),

        // 2. 中兴 (ZTE) 移动 WiFi & CPE 接口
        EndpointProbeDef(
            name: "ZTE 状态接口 (goform)",
            vendor: "中兴 (ZTE)",
            path: "/goform/goform_get_cmd_process?cmd=Language,cr_version,wa_inner_version,network_type,network_provider,signalbar,lte_rsrp,rscp,Nr_bands,nr5g_action_band,battery_value,wifi_access_sta_num,realtime_rx_thrpt,realtime_tx_thrpt,monthly_rx_bytes,day_rx_bytes,data_volume_clear_date,traffic_clear_date&multi_data=1"
        ),
        EndpointProbeDef(
            name: "ZTE API 状态接口",
            vendor: "中兴 (ZTE)",
            path: "/api/goform/goform_get_cmd_process?cmd=Language,cr_version,wa_inner_version,network_type,network_provider,signalbar,lte_rsrp,rscp,Nr_bands,nr5g_action_band,battery_value,wifi_access_sta_num,realtime_rx_thrpt,realtime_tx_thrpt,monthly_rx_bytes,day_rx_bytes,data_volume_clear_date,traffic_clear_date&multi_data=1"
        ),
        EndpointProbeDef(
            name: "ZTE 频段/网络详情",
            vendor: "中兴 (ZTE)",
            path: "/goform/goform_get_cmd_process?cmd=network_information&multi_data=1"
        ),
        EndpointProbeDef(
            name: "ZTE 电池/连接状态",
            vendor: "中兴 (ZTE)",
            path: "/goform/goform_get_cmd_process?cmd=battery_value,battery_charging,ppp_status&multi_data=1"
        ),
        EndpointProbeDef(
            name: "ZTE RD 鉴权参数",
            vendor: "中兴 (ZTE)",
            path: "/goform/goform_get_cmd_process?cmd=RD&isTest=false"
        ),

        // 3. UFI-TOOLS / MiniKano / Android 随身 WiFi (2333 端口 & 默认端口)
        EndpointProbeDef(
            name: "UFI 设备信息 (:2333)",
            vendor: "UFI-TOOLS",
            path: "/api/baseDeviceInfo",
            portOverride: 2333
        ),
        EndpointProbeDef(
            name: "UFI 信号指标 (:2333)",
            vendor: "UFI-TOOLS",
            path: "/api/signalDeviceInfo",
            portOverride: 2333
        ),
        EndpointProbeDef(
            name: "UFI 蜂窝用量 (:2333)",
            vendor: "UFI-TOOLS",
            path: "/api/cellularUsage",
            portOverride: 2333
        ),
        EndpointProbeDef(
            name: "UFI 网卡设备 (:2333)",
            vendor: "UFI-TOOLS",
            path: "/api/networkDeviceInfo",
            portOverride: 2333
        ),
        EndpointProbeDef(
            name: "UFI 默认端口基础信息",
            vendor: "UFI-TOOLS",
            path: "/api/baseDeviceInfo"
        ),

        // 4. 华为 (Huawei HiLink / 5G CPE) 接口
        EndpointProbeDef(name: "Huawei 状态接口", vendor: "华为 (HiLink)", path: "/api/monitoring/status"),
        EndpointProbeDef(name: "Huawei 设备信息", vendor: "华为 (HiLink)", path: "/api/device/information"),
        EndpointProbeDef(name: "Huawei 流量统计", vendor: "华为 (HiLink)", path: "/api/monitoring/traffic-statistics"),
        EndpointProbeDef(name: "Huawei 运营商信息", vendor: "华为 (HiLink)", path: "/api/net/current-plmn"),
        EndpointProbeDef(name: "Huawei 会话Token", vendor: "华为 (HiLink)", path: "/api/webserver/token"),
        EndpointProbeDef(name: "Huawei SesTok 接口", vendor: "华为 (HiLink)", path: "/api/webserver/SesTok_Info"),

        // 5. 展锐 / 翱捷 (Unisoc / ASR) 随身 WiFi 方案
        EndpointProbeDef(
            name: "Unisoc 综合状态接口",
            vendor: "展锐/翱捷 (Unisoc/ASR)",
            path: "/reqproc/proc_get?cmd=get_network_info,get_device_info,get_sim_status,get_wan_traffic"
        ),
        EndpointProbeDef(
            name: "Unisoc 网络信息",
            vendor: "展锐/翱捷 (Unisoc/ASR)",
            path: "/action/get_network_info"
        ),
        EndpointProbeDef(
            name: "Unisoc QCMAP 接口",
            vendor: "高通/展锐 (QCMAP)",
            path: "/cgi-bin/qcmap_web_cgi?page=status"
        ),
        EndpointProbeDef(
            name: "Unisoc QCMAP Auth",
            vendor: "高通/展锐 (QCMAP)",
            path: "/cgi-bin/qcmap_auth"
        ),

        // 6. 高通骁龙 5G 方案 (Qualcomm X55 / X62 / X65 MiFi & CPE)
        EndpointProbeDef(
            name: "Qualcomm 状态接口",
            vendor: "高通 (Qualcomm)",
            path: "/cgi-bin/te_web_cgi?cmd=get_device_info"
        ),
        EndpointProbeDef(
            name: "Qualcomm Webget 状态",
            vendor: "高通 (Qualcomm)",
            path: "/api/webget?cmd=status_info"
        ),
        EndpointProbeDef(
            name: "Qualcomm Status Info",
            vendor: "高通 (Qualcomm)",
            path: "/api/status_info"
        ),
        EndpointProbeDef(
            name: "Quectel 5G 网络接口",
            vendor: "Quectel/通用CPE",
            path: "/api/v1/network"
        ),

        // 7. 联发科 MTK 方案 (MTK T750 5G CPE & MiFi)
        EndpointProbeDef(
            name: "MTK Goform 网络接口",
            vendor: "联发科 (MTK)",
            path: "/goform/get_network_info"
        ),
        EndpointProbeDef(
            name: "MTK CPE Get 接口",
            vendor: "联发科 (MTK)",
            path: "/cgi-bin/cpe_get?cmd=network_info"
        ),

        // 8. OPPO / 飞猫 / 蒲公英 / OpenWrt / 通用 5G CPE 方案
        EndpointProbeDef(
            name: "OPPO 5G CPE 设备状态",
            vendor: "OPPO (CPE)",
            path: "/api/v1/device/status"
        ),
        EndpointProbeDef(
            name: "飞猫/通用 Ajax 状态",
            vendor: "飞猫/通用CPE",
            path: "/ajax/get_status"
        ),
        EndpointProbeDef(
            name: "蒲公英/通用 Web 状态",
            vendor: "蒲公英/MiFi",
            path: "/web/status"
        ),
        EndpointProbeDef(
            name: "OpenWrt / LuCI 状态",
            vendor: "OpenWrt/LuCI",
            path: "/cgi-bin/luci"
        ),
        EndpointProbeDef(
            name: "CPE 通用状态接口",
            vendor: "通用 5G CPE",
            path: "/api/status"
        ),
        EndpointProbeDef(
            name: "CPE WAN 状态接口",
            vendor: "通用 5G CPE",
            path: "/api/wan_status"
        ),
        EndpointProbeDef(
            name: "通用路由器状态页",
            vendor: "通用 CPE/MiFi",
            path: "/status.asp"
        )
    ]

    public func executeProbe(
        baseURLString: String,
        category: FeedbackCategory = .deviceAdaptation,
        deviceModel: String = "",
        userNotes: String = "",
        contact: String = "",
        appState: AppStateSnapshot? = nil,
        screenshotBase64: String? = nil,
        candidateTokens: [String] = [],
        sessionCookie: String? = nil,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async -> DeviceDiagnosticReport {
        let cleanBase = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let targetHost = F50Configuration.displayAddress(from: cleanBase)

        let probeDefs = Self.defaultProbeDefs
        let total = Double(probeDefs.count)
        var results: [EndpointProbeResult] = []
        var discoveredScriptAPIs: [String] = []
        var scriptURLsToFetch: [URL] = []

        let concurrencyLimit = 6
        var probeIndex = 0

        while probeIndex < probeDefs.count {
            let chunk = Array(probeDefs[probeIndex..<min(probeIndex + concurrencyLimit, probeDefs.count)])
            let chunkResults = await withTaskGroup(of: EndpointProbeResult.self) { group in
                for probeDef in chunk {
                    group.addTask {
                        let probeURL = self.resolveProbeURL(hostOrBase: targetHost, probeDef: probeDef)
                        return await self.probeSingleEndpoint(
                            url: probeURL,
                            probeDef: probeDef,
                            candidateTokens: candidateTokens,
                            sessionCookie: sessionCookie
                        )
                    }
                }
                var resList: [EndpointProbeResult] = []
                for await res in group {
                    resList.append(res)
                }
                return resList
            }

            results.append(contentsOf: chunkResults)

            for result in chunkResults {
                if (result.url.hasSuffix("/") || result.url.contains("index.html") || result.url.contains("login.html"))
                    && result.statusCode == 200 {
                    let apis = self.extractScriptAPIs(from: result.responseSnippet)
                    for api in apis where !discoveredScriptAPIs.contains(api) {
                        discoveredScriptAPIs.append(api)
                    }
                    if let baseURL = URL(string: result.url) {
                        let scriptUrls = self.extractScriptURLs(from: result.responseSnippet, baseURL: baseURL)
                        for surl in scriptUrls where !scriptURLsToFetch.contains(surl) {
                            scriptURLsToFetch.append(surl)
                        }
                    }
                }
            }

            probeIndex += concurrencyLimit
            let progress = min(1.0, Double(results.count) / total)
            onProgress?(progress, "已完成 \(results.count)/\(probeDefs.count) 个接口并发探测...")
        }

        // 进一步抓取前端外挂 JS Bundle，发现深度 API
        if !scriptURLsToFetch.isEmpty {
            onProgress?(0.95, "正在分析 \(scriptURLsToFetch.count) 个 JS 脚本中的隐藏 API...")
            for scriptURL in scriptURLsToFetch.prefix(3) {
                let apis = await fetchScriptAndExtractAPIs(scriptURL: scriptURL)
                for api in apis where !discoveredScriptAPIs.contains(api) {
                    discoveredScriptAPIs.append(api)
                }
            }
        }

        onProgress?(1.0, "诊断探测完成！")

        let osName = ProcessInfo.processInfo.operatingSystemVersionString
        return DeviceDiagnosticReport(
            category: category,
            appVersion: appVersion,
            osVersion: osName,
            deviceModel: deviceModel,
            userNotes: userNotes,
            contact: contact,
            targetBaseURL: cleanBase,
            appState: appState,
            screenshotBase64: screenshotBase64,
            endpoints: results,
            discoveredScriptAPIs: discoveredScriptAPIs.isEmpty ? nil : discoveredScriptAPIs
        )
    }

    private func extractScriptURLs(from htmlText: String, baseURL: URL) -> [URL] {
        var scriptURLs: [URL] = []
        let pattern = #"<script[^>]+src=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return scriptURLs }
        let matches = regex.matches(in: htmlText, options: [], range: NSRange(location: 0, length: htmlText.utf16.count))
        for match in matches {
            if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: htmlText) {
                let src = String(htmlText[range])
                if let url = URL(string: src, relativeTo: baseURL)?.absoluteURL,
                   !scriptURLs.contains(url) {
                    scriptURLs.append(url)
                }
            }
        }
        return Array(scriptURLs.prefix(4))
    }

    private func fetchScriptAndExtractAPIs(scriptURL: URL) async -> [String] {
        var request = URLRequest(url: scriptURL)
        request.timeoutInterval = 3.0
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              data.count <= 350 * 1024,
              let jsText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return []
        }
        return extractScriptAPIs(from: jsText)
    }

    private func extractScriptAPIs(from htmlText: String) -> [String] {
        var found: [String] = []
        let patterns = [
            #"/(?:api|goform|reqproc|cgi-bin|ajax)/[a-zA-Z0-9_\-\./]+"#,
            #"["']((?:api|goform|reqproc|cgi-bin)/[a-zA-Z0-9_\-\./]+)["']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: htmlText, options: [], range: NSRange(location: 0, length: htmlText.utf16.count))
            for match in matches {
                if let range = Range(match.range, in: htmlText) {
                    let path = String(htmlText[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    if !found.contains(path) && path.count < 80 {
                        found.append(path)
                    }
                }
            }
        }
        return found
    }

    private func resolveProbeURL(hostOrBase: String, probeDef: EndpointProbeDef) -> URL? {
        let cleanHost = hostOrBase.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        var scheme = "http"
        var rawHost = cleanHost
        var port: Int? = nil

        if cleanHost.hasPrefix("https://") {
            scheme = "https"
            rawHost = String(cleanHost.dropFirst(8))
        } else if cleanHost.hasPrefix("http://") {
            scheme = "http"
            rawHost = String(cleanHost.dropFirst(7))
        }

        if let colonIndex = rawHost.firstIndex(of: ":") {
            let hostPart = String(rawHost[..<colonIndex])
            let portPart = String(rawHost[rawHost.index(after: colonIndex)...])
            rawHost = hostPart
            port = Int(portPart)
        }

        if let overridePort = probeDef.portOverride {
            if F50Configuration.isIPAddress(rawHost) || rawHost == "localhost" {
                port = overridePort
            }
        }

        var urlString = "\(scheme)://\(rawHost)"
        if let p = port, p != 80 && p != 443 {
            urlString += ":\(p)"
        }
        urlString += probeDef.path

        return URL(string: urlString)
    }

    private func probeSingleEndpoint(
        url: URL?,
        probeDef: EndpointProbeDef,
        candidateTokens: [String] = [],
        sessionCookie: String? = nil
    ) async -> EndpointProbeResult {
        guard let url else {
            return EndpointProbeResult(
                name: probeDef.name,
                vendor: probeDef.vendor,
                url: probeDef.path,
                method: probeDef.method,
                statusCode: 0,
                statusText: "URL 构造失败",
                latencyMs: 0,
                contentType: "",
                serverHeader: "",
                responseSnippet: "",
                isSuccess: false
            )
        }

        // 1. 匿名常规探测（或带 Session Cookie）
        let (firstResult, statusCode) = await performHTTPRequest(
            url: url,
            probeDef: probeDef,
            token: nil,
            sessionCookie: sessionCookie
        )

        // 2. 如果返回 401/403，依次使用候选 Token 数组及 kano-sign 签名轮询尝试
        if (statusCode == 401 || statusCode == 403) && !candidateTokens.isEmpty {
            for token in candidateTokens {
                guard !token.isEmpty else { continue }
                let (authResult, authStatus) = await performHTTPRequest(
                    url: url,
                    probeDef: probeDef,
                    token: token,
                    sessionCookie: sessionCookie
                )
                if (200...299).contains(authStatus) || authResult.isSuccess {
                    return authResult
                }
            }
        }

        return firstResult
    }

    private func performHTTPRequest(
        url: URL,
        probeDef: EndpointProbeDef,
        token: String?,
        sessionCookie: String?
    ) async -> (EndpointProbeResult, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = probeDef.method
        request.timeoutInterval = 3.5
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) F50Monitor/2.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        if let host = url.host {
            let scheme = url.scheme ?? "http"
            let portStr = url.port != nil && url.port != 80 ? ":\(url.port!)" : ""
            request.setValue("\(scheme)://\(host)\(portStr)/index.html", forHTTPHeaderField: "Referer")
            request.setValue("\(scheme)://\(host)\(portStr)", forHTTPHeaderField: "Origin")
        }

        if let cookie = sessionCookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        var authModeUsed: String? = nil
        if let token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "token")
            request.setValue("admin", forHTTPHeaderField: "user")

            let ts = String(Int64(Date().timeIntervalSince1970 * 1000))
            let signData = "minikano\(probeDef.method)\(url.path)\(ts)"
            let sign = F50ResponseParser.kanoSign(key: F50Configuration.kanoSignKey, data: signData)
            request.setValue(sign, forHTTPHeaderField: "kano-sign")
            request.setValue(ts, forHTTPHeaderField: "kano-t")
            request.setValue(token, forHTTPHeaderField: "authorization")
            authModeUsed = "Candidate Token + KanoSign"
        } else if let cookie = sessionCookie, !cookie.isEmpty {
            authModeUsed = "Router Cookie Session"
        }

        for (k, v) in probeDef.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (data, response) = try await session.data(for: request)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                let res = EndpointProbeResult(
                    name: probeDef.name,
                    vendor: probeDef.vendor,
                    url: url.absoluteString,
                    method: probeDef.method,
                    statusCode: 0,
                    statusText: "非 HTTP 响应",
                    latencyMs: elapsedMs,
                    contentType: "",
                    serverHeader: "",
                    responseSnippet: "",
                    isSuccess: false,
                    authUsed: authModeUsed
                )
                return (res, 0)
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            let server = httpResponse.value(forHTTPHeaderField: "Server") ?? ""
            let rawBody = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? ""

            let sanitizedBody = DiagnosticSanitizer.sanitizeResponseSnippet(rawBody, contentType: contentType)
            let isSuccess = (200...299).contains(httpResponse.statusCode) && !sanitizedBody.isEmpty

            let res = EndpointProbeResult(
                name: probeDef.name,
                vendor: probeDef.vendor,
                url: url.absoluteString,
                method: probeDef.method,
                statusCode: httpResponse.statusCode,
                statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                latencyMs: elapsedMs,
                contentType: contentType,
                serverHeader: server,
                responseSnippet: sanitizedBody,
                isSuccess: isSuccess,
                authUsed: authModeUsed
            )
            return (res, httpResponse.statusCode)
        } catch {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let res = EndpointProbeResult(
                name: probeDef.name,
                vendor: probeDef.vendor,
                url: url.absoluteString,
                method: probeDef.method,
                statusCode: 0,
                statusText: (error as NSError).localizedDescription,
                latencyMs: elapsedMs,
                contentType: "",
                serverHeader: "",
                responseSnippet: "",
                isSuccess: false,
                authUsed: authModeUsed
            )
            return (res, 0)
        }
    }

    public func submitReportRemote(
        report: DeviceDiagnosticReport,
        webhookURL: URL
    ) async throws -> (success: Bool, message: String) {
        guard let jsonData = report.toJSONData() else {
            throw NSError(domain: "F50Diagnostic", code: -1, userInfo: [NSLocalizedDescriptionKey: "序列化诊断报告失败"])
        }
        guard jsonData.count <= DeviceDiagnosticReport.maxPayloadBytes else {
            throw NSError(domain: "F50Diagnostic", code: -3, userInfo: [NSLocalizedDescriptionKey: "诊断数据超过 512 KB 限制，请移除截图后重试"])
        }

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("F50Monitor/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")", forHTTPHeaderField: "User-Agent")
        request.setValue("f50-feedback-v1", forHTTPHeaderField: "X-F50-Feedback-Key")
        request.setValue(String(Int64(Date().timeIntervalSince1970 * 1000)), forHTTPHeaderField: "X-F50-Feedback-Timestamp")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-F50-Feedback-Request-Id")
        request.timeoutInterval = 15.0
        request.httpBody = jsonData

        let (data, response) = try await publicSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "F50Diagnostic", code: -2, userInfo: [NSLocalizedDescriptionKey: "无响应"])
        }

        if (200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String {
                if let issueUrl = json["issueUrl"] as? String, !issueUrl.isEmpty {
                    return (true, "\(msg) (Issue: \(issueUrl))")
                }
                return (true, msg)
            }
            let respStr = String(data: data, encoding: .utf8) ?? "提交成功"
            return (true, respStr)
        } else {
            let errStr = String(data: data, encoding: .utf8) ?? "HTTP 错误: \(http.statusCode)"
            return (false, errStr)
        }
    }
}

import Foundation
import CryptoKit

/// 华为 HiLink CPE 的本地 WebUI 协议适配层。
/// 仅使用用户已登录的设备管理接口；不尝试启用调试、Telnet 或修改设备配置。
final class HuaweiHiLinkAdapter {
    private let baseURL: URL
    private let session: URLSession
    private var token: String?

    init?(baseURLString: String) {
        let normalized = F50Configuration.normalizeBaseURL(baseURLString)
        guard let baseURL = URL(string: normalized) else { return nil }
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: configuration)
    }

    func probe() async -> Bool {
        guard let response = try? await get("api/device/basic_information") else { return false }
        let deviceName = response["DeviceName"] ?? response["devicename"] ?? ""
        let classify = response["Classify"] ?? response["classify"] ?? ""
        return !deviceName.isEmpty || classify.lowercased().contains("hilink") || classify.lowercased().contains("cpe")
    }

    func fetchStatus(password: String, includeTraffic: Bool) async throws -> [String: Any] {
        // 只读接口在许多固件上可匿名访问；若被运营商固件限制，使用用户填写的后台密码登录。
        if !password.isEmpty { try await loginIfNeeded(password: password) }

        async let monitoring = get("api/monitoring/status")
        async let signal = get("api/device/signal")
        async let device = get("api/device/information")
        async let traffic: [String: String]? = includeTraffic ? (try? await get("api/monitoring/traffic-statistics")) : nil

        let monitoringResponse = try await monitoring
        let signalResponse = (try? await signal) ?? [:]
        let deviceResponse = (try? await device) ?? [:]
        let trafficResponse = await traffic ?? [:]
        return normalizedStatus(monitoring: monitoringResponse, signal: signalResponse, device: deviceResponse, traffic: trafficResponse)
    }

    func fetchMessages(password: String) async throws -> [F50SMSMessage] {
        try await loginIfNeeded(password: password)
        let data = try await postData("api/sms/sms-list", body: [
            "PageIndex": "1", "ReadCount": "100", "BoxType": "1", "SortType": "0",
            "Ascending": "0", "UnreadPreferred": "0"
        ])
        return XMLSMSParser.parse(data)
    }

    func sendMessage(to number: String, content: String, password: String) async throws {
        try await loginIfNeeded(password: password)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let response = try await post("api/sms/send-sms", body: [
            "Index": "-1", "Phones": ["Phone": number], "Sca": "", "Content": content,
            "Length": String(content.utf8.count), "Reserved": "1", "Date": formatter.string(from: Date()), "SendType": "0"
        ])
        guard response["response"]?.uppercased() == "OK" || response["result"]?.uppercased() == "OK" || response["Response"]?.uppercased() == "OK" else {
            throw HuaweiHiLinkError.requestFailed("设备未确认短信发送")
        }
    }

    private func loginIfNeeded(password: String) async throws {
        if token == nil { try await refreshToken() }
        let state = try? await get("api/user/state-login")
        if state?["State"] == "0" { return }

        let passwordType = state?["password_type"] ?? "0"
        let encoded: String
        if passwordType == "0" {
            encoded = Data(password.utf8).base64EncodedString()
        } else if let token, !token.isEmpty {
            let passwordHash = SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
            let concentrated = "admin" + Data(passwordHash.utf8).base64EncodedString() + token
            let finalHash = SHA256.hash(data: Data(concentrated.utf8)).map { String(format: "%02x", $0) }.joined()
            encoded = Data(finalHash.utf8).base64EncodedString()
        } else {
            throw HuaweiHiLinkError.unsupportedLogin(passwordType)
        }
        _ = try await post("api/user/login", body: [
            "Username": "admin", "Password": encoded, "password_type": passwordType
        ])
        try await refreshToken()
    }

    private func refreshToken() async throws {
        if let response = try? await get("api/webserver/token"), let token = response["token"], !token.isEmpty {
            self.token = token
            return
        }
        let response = try await get("api/webserver/SesTokInfo")
        guard let token = response["TokInfo"], !token.isEmpty else { throw HuaweiHiLinkError.missingToken }
        self.token = token
    }

    private func get(_ path: String) async throws -> [String: String] {
        var request = URLRequest(url: endpoint(path))
        request.timeoutInterval = 4
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let token { request.setValue(token, forHTTPHeaderField: "__RequestVerificationToken") }
        return try await perform(request)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: String] {
        XMLFlatParser.parse(try await postData(path, body: body))
    }

    private func postData(_ path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let token { request.setValue(token, forHTTPHeaderField: "__RequestVerificationToken") }
        request.httpBody = XMLRequestEncoder.encode(body)
        return try await performData(request)
    }

    private func perform(_ request: URLRequest) async throws -> [String: String] {
        XMLFlatParser.parse(try await performData(request))
    }

    private func performData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HuaweiHiLinkError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        if let nextToken = http.value(forHTTPHeaderField: "__RequestVerificationToken"), !nextToken.isEmpty { token = nextToken }
        let values = XMLFlatParser.parse(data)
        if let code = values["code"], code != "0" { throw HuaweiHiLinkError.requestFailed("设备错误 \(code)") }
        return data
    }

    private func endpoint(_ path: String) -> URL { baseURL.appendingPathComponent(path) }

    private func normalizedStatus(monitoring: [String: String], signal: [String: String], device: [String: String], traffic: [String: String]) -> [String: Any] {
        func first(_ keys: [String], in values: [String: String]) -> String? {
            keys.lazy.compactMap { key in
                values[key] ?? values.first { entry in entry.key.caseInsensitiveCompare(key) == .orderedSame }?.value
            }.first
        }
        func value(_ keys: [String]) -> String? {
            first(keys, in: signal) ?? first(keys, in: monitoring) ?? first(keys, in: device) ?? first(keys, in: traffic)
        }
        var result: [String: Any] = [:]
        result["network_type"] = value(["CurrentNetworkTypeEx", "CurrentNetworkType", "NetworkType"]) ?? ""
        result["network_provider"] = value(["CurrentServiceDomain", "OperatorName", "CurrentPLMN", "NetworkName"]) ?? ""
        result["signalbar"] = value(["SignalIcon", "signalbar"]) ?? "0"
        result["rsrp"] = value(["rsrp", "Rsrp", "RSRP"]) ?? ""
        result["rsrq"] = value(["rsrq", "Rsrq", "RSRQ"]) ?? ""
        result["sinr"] = value(["sinr", "Sinr", "SINR", "snr", "Snr"]) ?? ""
        result["ppp_status"] = value(["ConnectionStatus", "connectionstatus"]) ?? ""
        result["realtime_rx_thrpt"] = value(["CurrentDownloadRate", "DownloadRate"]) ?? "0"
        result["realtime_tx_thrpt"] = value(["CurrentUploadRate", "UploadRate"]) ?? "0"
        result["realtime_rx_bytes"] = value(["CurrentDownload", "CurrentDownloadBytes"]) ?? "0"
        result["realtime_tx_bytes"] = value(["CurrentUpload", "CurrentUploadBytes"]) ?? "0"
        result["monthly_rx_bytes"] = value(["MonthDownload", "MonthlyDownload"]) ?? "0"
        result["monthly_tx_bytes"] = value(["MonthUpload", "MonthlyUpload"]) ?? "0"
        result["wifi_access_sta_num"] = value(["CurrentWifiUser", "WlanUser", "WifiUserNumber"]) ?? "0"
        result["sms_unread_num"] = value(["UnreadMessage", "UnreadSMS", "SmsUnreadCount"]) ?? "0"
        return result
    }

}

private enum HuaweiHiLinkError: LocalizedError {
    case missingToken
    case unsupportedLogin(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "未取得华为 HiLink 会话令牌"
        case .unsupportedLogin(let type): return "该华为固件使用暂未支持的登录方式（\(type)）"
        case .requestFailed(let detail): return detail
        }
    }
}

private enum XMLRequestEncoder {
    static func encode(_ values: [String: Any]) -> Data {
        let body = values.map { key, value in element(key, value) }.joined()
        return Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><request>\(body)</request>".utf8)
    }

    private static func element(_ name: String, _ value: Any) -> String {
        if let dictionary = value as? [String: Any] {
            return "<\(name)>\(dictionary.map { element($0.key, $0.value) }.joined())</\(name)>"
        }
        let escaped = String(describing: value)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<\(name)>\(escaped)</\(name)>"
    }
}

private final class XMLFlatParser: NSObject, XMLParserDelegate {
    private var values: [String: String] = [:]
    private var currentElement = ""
    private var currentText = ""

    static func parse(_ data: Data) -> [String: String] {
        let delegate = XMLFlatParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { values[elementName] = value }
        currentElement = ""
        currentText = ""
    }
}

private final class XMLSMSParser: NSObject, XMLParserDelegate {
    private var messages: [[String: String]] = []
    private var message: [String: String]?
    private var currentElement = ""
    private var currentText = ""

    static func parse(_ data: Data) -> [F50SMSMessage] {
        let delegate = XMLSMSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.messages.compactMap { message in
            guard let id = message["Index"], !id.isEmpty else { return nil }
            let status = message["Smstat"] ?? "0"
            return F50SMSMessage(
                id: id,
                number: message["Phone"] ?? "",
                content: message["Content"] ?? "",
                dateText: message["Date"] ?? "",
                tag: status == "1" ? "1" : (message["SmsType"] == "2" ? "2" : "0")
            )
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "Message" { message = [:] }
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "Message" {
            if let message { messages.append(message) }
            message = nil
        } else if message != nil, !text.isEmpty {
            message?[elementName] = text
        }
        currentElement = ""
        currentText = ""
    }
}

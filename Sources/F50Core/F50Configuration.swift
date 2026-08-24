import Foundation

public enum F50Configuration {
    public static let defaultBaseURL = "http://192.168.0.1:2333"
    public static let defaultCredential = "admin"
    public static let defaultRefreshInterval = 2.0
    public static let trafficRefreshInterval = 30.0

    public static let baseURLDefaultsKey = "F50_BaseURL"
    public static let legacyPasswordDefaultsKey = "F50_Password"
    public static let legacyUFITokenDefaultsKey = "F50_UFIToken"
    public static let refreshIntervalDefaultsKey = "F50_RefreshInterval"
    public static let displayModeDefaultsKey = "F50_DisplayMode"
    public static let monthlyOffsetDefaultsKey = "F50_MonthlyOffsetBytes"
    public static let dailyOffsetDefaultsKey = "F50_DailyOffsetBytes"
    public static let screenMirroringEnabledDefaultsKey = "F50_ScreenMirroringEnabled"
    public static let screenMirroringPortDefaultsKey = "F50_ScreenMirroringPort"
    public static let defaultADBPort = 5555
    public static let trafficResetDayDefaultsKey = "F50_TrafficResetDay"
    public static let demoModeDefaultsKey = "F50_DemoMode"
    public static let initialSetupCompletedDefaultsKey = "F50_InitialSetupCompleted"

    // UFI-TOOLS 签名密钥（设备端协议固定值）
    public static let kanoSignKey = "minikano_kOyXz0Ciz4V7wR0IeKmJFYFQ20jd"
    // 设备检测到的流量清零日 / 每日流量追踪
    public static let detectedTrafficResetDayDefaultsKey = "F50_DetectedTrafficResetDay"
    public static let dailyTrafficDateDefaultsKey = "F50_DailyTrafficDate"
    public static let dailyTrafficStartBytesDefaultsKey = "F50_DailyTrafficStartBytes"

    /// 旧版本已保存过地址的用户无需再次经过首次设置。
    public static var needsInitialSetup: Bool {
        let defaults = UserDefaults.standard
        return !defaults.bool(forKey: initialSetupCompletedDefaultsKey)
            && defaults.object(forKey: baseURLDefaultsKey) == nil
    }

    /// 判断指定主机名是否为 IP 地址（IPv4 或包含冒号/方括号的 IPv6）
    public static func isIPAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        if parts.count == 4 && parts.allSatisfy({ Int($0) != nil && (0...255).contains(Int($0)!) }) {
            return true
        }
        if host.contains(":") || (host.hasPrefix("[") && host.hasSuffix("]")) {
            return true
        }
        return false
    }

    /// 解析 baseURLString，返回对应的 Router 地址和 UFI 地址
    /// 规则：
    /// 1. IP 地址且未指定非 2333 端口时：Router 为 http://<ip> (80 端口)，UFI 为 http://<ip>:2333 (2333 端口)
    /// 2. 域名（内网穿透/反向代理场景）且未显式指定端口时：忽略 2333 端口，直接使用域名（例如 http://f50.example.com）连接 Router 和 UFI
    /// 3. 若显式指定了自定义端口（如 8443）：Router 与 UFI 均使用该指定端口
    public static func resolveEndpoints(from raw: String) -> (routerBaseURL: String, ufiBaseURL: String) {
        let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n\r"))
        guard !clean.isEmpty else {
            return ("http://192.168.0.1", "http://192.168.0.1:2333")
        }

        let withScheme = clean.contains("://") ? clean : "http://" + clean
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else {
            return ("http://192.168.0.1", "http://192.168.0.1:2333")
        }

        let scheme = url.scheme?.lowercased() ?? "http"
        let isIP = isIPAddress(host)

        if let port = url.port {
            if isIP && port == 2333 {
                return ("\(scheme)://\(host)", "\(scheme)://\(host):2333")
            } else {
                return ("\(scheme)://\(host):\(port)", "\(scheme)://\(host):\(port)")
            }
        } else {
            if isIP {
                return ("\(scheme)://\(host)", "\(scheme)://\(host):2333")
            } else {
                // 域名且未指定端口：内网穿透直连域名（不追加 2333 端口）
                let base = "\(scheme)://\(host)"
                return (base, base)
            }
        }
    }

    /// 提取用于在设置界面中显示的友好地址字符串（去除默认 scheme 和默认 2333 端口）
    public static func displayAddress(from raw: String) -> String {
        let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n\r"))
        guard !clean.isEmpty else { return "192.168.0.1" }
        let withScheme = clean.contains("://") ? clean : "http://" + clean
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else {
            return clean
        }
        let scheme = url.scheme?.lowercased() ?? "http"
        let isIP = isIPAddress(host)

        if scheme == "https" {
            if let port = url.port {
                return "https://\(host):\(port)"
            }
            return "https://\(host)"
        }

        if let port = url.port {
            if isIP && port == 2333 {
                return host
            }
            return "\(host):\(port)"
        }
        return host
    }

    /// 规范化保存的 baseURLString
    public static func normalizeBaseURL(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n\r"))
        guard !clean.isEmpty else { return defaultBaseURL }
        let withScheme = clean.contains("://") ? clean : "http://" + clean
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else {
            return defaultBaseURL
        }
        let scheme = url.scheme?.lowercased() ?? "http"
        let isIP = isIPAddress(host)

        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        } else {
            if isIP {
                return "\(scheme)://\(host):2333"
            } else {
                return "\(scheme)://\(host)"
            }
        }
    }

    /// 校验地址（支持 IPv4 地址或合法的域名/主机名，允许携带自定义端口和协议）
    public static func isValidAddress(_ raw: String) -> Bool {
        let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n\r"))
        guard !clean.isEmpty else { return false }
        let withScheme = clean.contains("://") ? clean : "http://" + clean
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else {
            return false
        }
        guard !host.contains(" ") && !host.contains("/") else { return false }

        let parts = host.split(separator: ".")
        let allNumeric = !parts.isEmpty && parts.allSatisfy { Int($0) != nil }

        if allNumeric {
            guard parts.count == 4 else { return false }
            return parts.allSatisfy { part in
                if let num = Int(part), (0...255).contains(num) {
                    return true
                }
                return false
            }
        }

        if host.lowercased() == "localhost" {
            return true
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard host.rangeOfCharacter(from: allowed.inverted) == nil else { return false }
        guard host.contains(".") else { return false }
        guard !host.hasPrefix(".") && !host.hasSuffix(".") else { return false }
        guard parts.allSatisfy({ !$0.isEmpty }) else { return false }

        return true
    }
}

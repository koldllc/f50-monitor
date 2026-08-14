import Foundation

enum F50Configuration {
    static let defaultBaseURL = "http://192.168.0.1:2333"
    static let defaultCredential = "admin"
    static let defaultRefreshInterval = 2.0
    static let trafficRefreshInterval = 30.0

    static let baseURLDefaultsKey = "F50_BaseURL"
    static let legacyPasswordDefaultsKey = "F50_Password"
    static let legacyUFITokenDefaultsKey = "F50_UFIToken"
    static let refreshIntervalDefaultsKey = "F50_RefreshInterval"
    static let displayModeDefaultsKey = "F50_DisplayMode"
    static let monthlyOffsetDefaultsKey = "F50_MonthlyOffsetBytes"
    static let dailyOffsetDefaultsKey = "F50_DailyOffsetBytes"
    static let screenMirroringEnabledDefaultsKey = "F50_ScreenMirroringEnabled"
    static let screenMirroringPortDefaultsKey = "F50_ScreenMirroringPort"
    static let defaultADBPort = 5555
    static let trafficResetDayDefaultsKey = "F50_TrafficResetDay"

    // UFI-TOOLS 签名密钥（设备端协议固定值）
    static let kanoSignKey = "minikano_kOyXz0Ciz4V7wR0IeKmJFYFQ20jd"
    // 设备检测到的流量清零日 / 每日流量追踪
    static let detectedTrafficResetDayDefaultsKey = "F50_DetectedTrafficResetDay"
    static let dailyTrafficDateDefaultsKey = "F50_DailyTrafficDate"
    static let dailyTrafficStartBytesDefaultsKey = "F50_DailyTrafficStartBytes"
}



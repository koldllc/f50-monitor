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

    // UFI-TOOLS 签名密钥（设备端协议固定值）
    public static let kanoSignKey = "minikano_kOyXz0Ciz4V7wR0IeKmJFYFQ20jd"
    // 设备检测到的流量清零日 / 每日流量追踪
    public static let detectedTrafficResetDayDefaultsKey = "F50_DetectedTrafficResetDay"
    public static let dailyTrafficDateDefaultsKey = "F50_DailyTrafficDate"
    public static let dailyTrafficStartBytesDefaultsKey = "F50_DailyTrafficStartBytes"
}

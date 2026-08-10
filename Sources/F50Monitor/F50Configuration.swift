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
}

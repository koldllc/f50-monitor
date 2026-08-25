import Foundation
import Combine
import CryptoKit

final class F50NetworkDelegate: NSObject, URLSessionDelegate {
    static let shared = F50NetworkDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

@MainActor
public class F50Fetcher: ObservableObject {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 8.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config, delegate: F50NetworkDelegate.shared, delegateQueue: nil)
    }()

    @Published public var status: F50Status = F50Status()
    @Published public var baseURLString: String {
        didSet {
            if baseURLString != oldValue {
                UserDefaults.standard.set(baseURLString, forKey: F50Configuration.baseURLDefaultsKey)
                if !isApplyingConfiguration { configurationDidChange() }
            }
        }
    }

    /// 路由器后台地址（例如 http://192.168.0.1 或 http://f50.example.com）
    public var routerURLString: String {
        F50Configuration.resolveEndpoints(from: baseURLString).routerBaseURL
    }

    /// 随身 WiFi / UFI 后台地址（例如 http://192.168.0.1:2333 或 http://f50.example.com）
    public var ufiURLString: String {
        F50Configuration.resolveEndpoints(from: baseURLString).ufiBaseURL
    }

    @Published public var password: String {
        didSet {
            if password != oldValue {
                KeychainCredentialStore.save(password, account: "router-password")
                if !isApplyingConfiguration { configurationDidChange() }
            }
        }
    }
    @Published public var ufiToken: String {
        didSet {
            if ufiToken != oldValue {
                KeychainCredentialStore.save(ufiToken, account: "ufi-token")
                if !isApplyingConfiguration { configurationDidChange() }
            }
        }
    }
    @Published public var refreshInterval: Double {
        didSet {
            if refreshInterval != oldValue {
                UserDefaults.standard.set(refreshInterval, forKey: F50Configuration.refreshIntervalDefaultsKey)
                restartTimer()
            }
        }
    }
    @Published public var displayMode: MenuBarDisplayMode {
        didSet {
            if displayMode != oldValue {
                if let data = try? JSONEncoder().encode(displayMode) {
                    UserDefaults.standard.set(data, forKey: F50Configuration.displayModeDefaultsKey)
                }
            }
        }
    }
    @Published public private(set) var smsMessages: [F50SMSMessage] = []
    @Published public private(set) var isFetchingSMS = false
    @Published public private(set) var smsErrorMessage: String?
    public private(set) var locallyReadSMSIds: Set<String> = []
    private var smsAutoRefreshTimer: Timer?

    @Published public var isDemoMode: Bool {
        didSet {
            if isDemoMode != oldValue {
                UserDefaults.standard.set(isDemoMode, forKey: F50Configuration.demoModeDefaultsKey)
                configurationDidChange()
                if isDemoMode {
                    applyDemoData()
                } else {
                    demoTick = 0
                    // 退出演示模式后先清空模拟状态，避免真实设备连接失败时
                    // 将残留的演示指标写入反馈或继续展示在 Widget 中。
                    status = F50Status()
                    updateEffectiveTrafficResetDay()
                    F50WidgetDataStore.clear()
                    fetchData()
                    fetchSMSMessages()
                }
            }
        }
    }
    private var demoTick: Int = 0

    private var timer: Timer?
     public private(set) var isFetching = false
    private var sessionCookie: String? = nil
    private var requestGeneration: UInt = 0
    private var baseTask: URLSessionDataTask?
    private var bandTask: URLSessionDataTask?
    private var shellTask: URLSessionDataTask?
    private var qosTask: URLSessionDataTask?
    private var packageTask: URLSessionDataTask?
    private var smsTask: URLSessionDataTask?
    private var isFetchingExtensions = false
    private var isFetchingUFISupplement = false
    private var pendingExtensionRequests = 0
    private var isApplyingConfiguration = false
    private var lastTrafficRefreshDate = Date.distantPast
    private var lastADBHardwareRefreshDate = Date.distantPast
    private var lastADBQosRefreshDate = Date.distantPast
    private let adbHardwareRefreshInterval: TimeInterval = 10
    // QCI 主要由连接上下文变化触发；5 分钟轮询仅用于设备未上报变化时兜底。
    private let adbQosRefreshInterval: TimeInterval = 300

    // token 候选缓存：凭据不变时避免每个轮询周期重复计算 SHA-256
    private var cachedCandidateTokens: [String]?
    private var cachedTokenSource = ""

    // CPU delta tracking
    private var prevTotalCpu: Double = 0
    private var prevIdleCpu: Double = 0
    private var routerDetectedTrafficResetDay: Int = 0
    private var huaweiAdapter: HuaweiHiLinkAdapter?
    private var hasProbedHuawei = false

    // Ring Log Buffer (脱敏诊断日志)
    private var ringLogBuffer: [String] = []
    private let maxLogCount = 100
    private var diagnosticFirmwareVersion = ""
    private var diagnosticChannelMode = "未知"

    public func appendLog(_ category: String, _ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let formatted = "[\(ts)] [\(category)] \(message)"
        ringLogBuffer.append(formatted)
        if ringLogBuffer.count > maxLogCount {
            ringLogBuffer.removeFirst(ringLogBuffer.count - maxLogCount)
        }
    }

    public var currentDiagnosticFirmwareVersion: String { diagnosticFirmwareVersion }
    public var currentDiagnosticChannelMode: String { diagnosticChannelMode }

    public func getRecentLogs() -> [String] {
        return ringLogBuffer
    }

    public func getCandidateTokensPublic() -> [String] {
        return candidateTokens()
    }

    public var currentSessionCookie: String? {
        return sessionCookie
    }

    // Network throughput tracking
    private var prevNetDevRx: UInt64 = 0
    private var prevNetDevTx: UInt64 = 0
    private var prevNetDevTimestamp: Date? = nil

    @Published public var monthlyOffsetBytes: Int64
    @Published public var dailyOffsetBytes: Int64
    @Published public var trafficResetDay: Int {
        didSet {
            if trafficResetDay != oldValue {
                UserDefaults.standard.set(trafficResetDay, forKey: F50Configuration.trafficResetDayDefaultsKey)
                updateEffectiveTrafficResetDay()
            }
        }
    }

    private func updateEffectiveTrafficResetDay() {
        let effectiveDay: Int
        if (1...31).contains(routerDetectedTrafficResetDay) {
            effectiveDay = routerDetectedTrafficResetDay
        } else if (1...31).contains(trafficResetDay) {
            effectiveDay = trafficResetDay
        } else {
            let savedDetected = UserDefaults.standard.integer(forKey: "F50_DetectedTrafficResetDay")
            effectiveDay = (1...31).contains(savedDetected) ? savedDetected : 0
        }
        self.status.trafficResetDay = effectiveDay
    }

    public init() {
        self.baseURLString = UserDefaults.standard.string(forKey: F50Configuration.baseURLDefaultsKey)
            ?? F50Configuration.defaultBaseURL
        self.password = KeychainCredentialStore.loadMigratingLegacyValue(
            account: "router-password",
            legacyDefaultsKey: F50Configuration.legacyPasswordDefaultsKey
        )
        self.ufiToken = KeychainCredentialStore.loadMigratingLegacyValue(
            account: "ufi-token",
            legacyDefaultsKey: F50Configuration.legacyUFITokenDefaultsKey
        )

        let savedInterval = UserDefaults.standard.double(forKey: F50Configuration.refreshIntervalDefaultsKey)
        self.refreshInterval = savedInterval > 0 ? savedInterval : F50Configuration.defaultRefreshInterval

        // 保留用户手动设置（若有），否则置为 0（未知），等待设备上报或使用默认值
        let savedManualDay = UserDefaults.standard.integer(forKey: F50Configuration.trafficResetDayDefaultsKey)
        self.trafficResetDay = (1...31).contains(savedManualDay) ? savedManualDay : 0

        let savedDetectedDay = UserDefaults.standard.integer(forKey: "F50_DetectedTrafficResetDay")
        if savedDetectedDay > 0 && savedDetectedDay <= 31 {
            self.routerDetectedTrafficResetDay = savedDetectedDay
        }

        self.monthlyOffsetBytes = (UserDefaults.standard.object(forKey: F50Configuration.monthlyOffsetDefaultsKey) as? Int64)
            ?? (UserDefaults.standard.object(forKey: F50Configuration.monthlyOffsetDefaultsKey) as? NSNumber)?.int64Value ?? 0
        self.dailyOffsetBytes = (UserDefaults.standard.object(forKey: F50Configuration.dailyOffsetDefaultsKey) as? Int64)
            ?? (UserDefaults.standard.object(forKey: F50Configuration.dailyOffsetDefaultsKey) as? NSNumber)?.int64Value ?? 0

        if let modeData = UserDefaults.standard.data(forKey: F50Configuration.displayModeDefaultsKey),
           let mode = try? JSONDecoder().decode(MenuBarDisplayMode.self, from: modeData) {
            self.displayMode = mode
        } else {
            self.displayMode = .speeds
        }

        self.locallyReadSMSIds = Set(UserDefaults.standard.stringArray(forKey: "F50_LocallyReadSMSIds") ?? [])
        self.isDemoMode = UserDefaults.standard.bool(forKey: F50Configuration.demoModeDefaultsKey)

        if !self.locallyReadSMSIds.isEmpty {
            self.status.smsUnreadCount = 0
        }

        if self.isDemoMode {
            self.status = F50Status.mockStatus(tick: 0)
            self.smsMessages = F50SMSMessage.mockMessages
            self.status.smsUnreadCount = self.smsMessages.filter { $0.isUnread }.count
        }

        updateEffectiveTrafficResetDay()
        startTimer()
        fetchData()
        fetchSMSMessages()
    }

    public func applyDemoData() {
        self.status = F50Status.mockStatus(tick: demoTick)
        self.smsMessages = F50SMSMessage.mockMessages
        self.status.smsUnreadCount = self.smsMessages.filter { $0.isUnread }.count
        self.smsErrorMessage = nil
        self.isFetchingSMS = false
        F50WidgetDataStore.saveStatus(self.status)
    }

    public func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.fetchData()
            }
        }
    }

    public func restartTimer() {
        startTimer()
    }

    public func applyConfiguration(
        baseURL: String,
        password: String,
        ufiToken: String,
        refreshInterval: Double,
        displayMode: MenuBarDisplayMode,
        trafficResetDay: Int? = nil
    ) {
        let cleanBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let connectionChanged = cleanBaseURL != baseURLString
            || password != self.password
            || ufiToken != self.ufiToken

        isApplyingConfiguration = true
        baseURLString = cleanBaseURL
        self.password = password
        self.ufiToken = ufiToken
        self.refreshInterval = refreshInterval
        self.displayMode = displayMode
        if let resetDay = trafficResetDay, (0...31).contains(resetDay) {
            self.trafficResetDay = resetDay
        }
        updateEffectiveTrafficResetDay()
        isApplyingConfiguration = false

        if connectionChanged {
            configurationDidChange()
        }
        fetchData()
    }

    public func fetchData() {
        if isDemoMode {
            demoTick += 1
            self.status = F50Status.mockStatus(tick: demoTick)
            F50WidgetDataStore.saveStatus(self.status)
            return
        }

        guard !isFetching else { return }
        appendLog("连接", "开始刷新 Router/UFI 状态")
        isFetching = true
        let generation = requestGeneration

        let cleanBase = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let endpoints = connectionEndpoints(from: cleanBase)

        let shouldRefreshTraffic = Date().timeIntervalSince(lastTrafficRefreshDate)
            >= F50Configuration.trafficRefreshInterval

        if let huaweiAdapter {
            fetchHuaweiStatus(huaweiAdapter, generation: generation, refreshTraffic: shouldRefreshTraffic)
            return
        }

        if !hasProbedHuawei, let adapter = HuaweiHiLinkAdapter(baseURLString: cleanBase) {
            hasProbedHuawei = true
            Task { [weak self] in
                guard let self else { return }
                if await adapter.probe() {
                    guard generation == self.requestGeneration else { return }
                    self.huaweiAdapter = adapter
                    self.fetchHuaweiStatus(adapter, generation: generation, refreshTraffic: shouldRefreshTraffic)
                } else {
                    guard generation == self.requestGeneration else { return }
                    self.executeFetch(
                        cleanBase: cleanBase,
                        hostOnly: endpoints.routerBaseURL,
                        ufiBaseURL: endpoints.ufiBaseURL,
                        generation: generation,
                        refreshTraffic: shouldRefreshTraffic,
                        allowsUFIFallback: true
                    )
                }
            }
            return
        }

        // 所有连接统一从 Router/Goform 开始；缺失项再依次尝试 ADB 与 UFI。
        executeFetch(
            cleanBase: cleanBase,
            hostOnly: endpoints.routerBaseURL,
            ufiBaseURL: endpoints.ufiBaseURL,
            generation: generation,
            refreshTraffic: shouldRefreshTraffic,
            allowsUFIFallback: true
        )
    }

    private func fetchHuaweiStatus(_ adapter: HuaweiHiLinkAdapter, generation: UInt, refreshTraffic: Bool) {
        Task { [weak self] in
            do {
                let payload = try await adapter.fetchStatus(password: self?.password ?? "", includeTraffic: refreshTraffic)
                guard let self, generation == self.requestGeneration else { return }
                self.parseStatusDict(payload, preserveQos: true, refreshTraffic: refreshTraffic)
                self.diagnosticChannelMode = "Huawei HiLink"
                self.appendLog("连接", "Huawei HiLink CPE 状态读取成功")
                if refreshTraffic { self.lastTrafficRefreshDate = Date() }
                self.isFetching = false
                F50WidgetDataStore.saveStatus(self.status)
            } catch {
                guard let self, generation == self.requestGeneration else { return }
                self.updateStatusFailed("华为 HiLink: \(error.localizedDescription)", generation: generation)
            }
        }
    }

    public func fetchDataAsync() async {
        fetchData()
        guard !isDemoMode else { return }
        guard isFetching else { return }
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !isFetching { break }
        }
    }

    public func fetchSMSMessagesAsync() async {
        fetchSMSMessages()
        guard !isDemoMode else { return }
        guard isFetchingSMS else { return }
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !isFetchingSMS { break }
        }
    }

    public func fetchSMSMessages() {
        if isDemoMode {
            if self.smsMessages.isEmpty {
                self.smsMessages = F50SMSMessage.mockMessages
            }
            self.smsErrorMessage = nil
            self.isFetchingSMS = false
            return
        }

        guard !isFetchingSMS else { return }

        let generation = requestGeneration
        let cleanBase = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if let huaweiAdapter {
            isFetchingSMS = true
            smsErrorMessage = nil
            Task { [weak self] in
                do {
                    let messages = try await huaweiAdapter.fetchMessages(password: self?.password ?? "")
                    guard let self, generation == self.requestGeneration else { return }
                    let readIDs = self.locallyReadSMSIds
                    self.smsMessages = messages.map { message in
                        var copy = message
                        copy.isLocallyRead = readIDs.contains(message.id)
                        return copy
                    }
                    self.status.smsUnreadCount = self.smsMessages.filter(\.isUnread).count
                    self.isFetchingSMS = false
                } catch {
                    guard let self, generation == self.requestGeneration else { return }
                    self.finishSMSFetch(message: "华为 HiLink: \(error.localizedDescription)", generation: generation)
                }
            }
            return
        }
        let endpoints = connectionEndpoints(from: cleanBase)
        let tokens = candidateTokens()

        guard !tokens.isEmpty else {
            smsErrorMessage = "请先配置 UFI后台口令"
            return
        }

        isFetchingSMS = true
        smsErrorMessage = nil
        fetchSMSMessagesViaRouter(
            routerBaseURL: endpoints.routerBaseURL,
            ufiBaseURL: endpoints.ufiBaseURL,
            candidateTokens: tokens,
            generation: generation
        )
    }

    private func smsMessagesURL(baseURL: String, isUFIProxy: Bool) -> URL? {
        let path = isUFIProxy
            ? "/api/goform/goform_get_cmd_process"
            : "/goform/goform_get_cmd_process"
        guard var components = URLComponents(string: "\(baseURL)\(path)") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "multi_data", value: "1"),
            URLQueryItem(name: "isTest", value: "false"),
            URLQueryItem(name: "cmd", value: "sms_data_total"),
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "data_per_page", value: "100"),
            URLQueryItem(name: "mem_store", value: "1"),
            URLQueryItem(name: "tags", value: "100"),
            URLQueryItem(name: "order_by", value: "order by id desc"),
            URLQueryItem(name: "_", value: String(Int64(Date().timeIntervalSince1970 * 1000)))
        ]
        return components.url
    }

    private func fetchSMSMessagesViaRouter(
        routerBaseURL: String,
        ufiBaseURL: String,
        candidateTokens: [String],
        generation: UInt
    ) {
        guard generation == requestGeneration,
              let url = smsMessagesURL(baseURL: routerBaseURL, isUFIProxy: false) else {
            finishSMSFetch(message: "短信接口地址无效", generation: generation)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("\(routerBaseURL)/index.html", forHTTPHeaderField: "Referer")
        if let sessionCookie, !sessionCookie.isEmpty {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        smsTask = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                if let http = response as? HTTPURLResponse,
                   http.statusCode == 200,
                   let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   self.applySMSPayload(json) {
                    return
                }

                let host = URL(string: routerBaseURL)?.host ?? "192.168.0.1"
                if let localURL = self.smsMessagesURL(baseURL: "http://127.0.0.1", isUFIProxy: false) {
                    let urlText = localURL.absoluteString.replacingOccurrences(of: "'", with: "'\\''")
                    let adbCommand = "if command -v curl >/dev/null 2>&1; then curl -sS -H 'Referer: http://127.0.0.1/index.html' '\(urlText)'; elif command -v wget >/dev/null 2>&1; then wget -qO- --header='Referer: http://127.0.0.1/index.html' '\(urlText)'; fi"
                    if let output = await ADBHardwareFetcher.executeShell(
                        host: host,
                        port: 5555,
                        command: adbCommand,
                        timeoutSec: 2.0
                    ),
                       let adbData = output.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: adbData) as? [String: Any],
                       self.applySMSPayload(json) {
                        return
                    }
                }

                self.fetchSMSMessagesViaUFI(
                    ufiBaseURL: ufiBaseURL,
                    candidateTokens: candidateTokens,
                    generation: generation
                )
            }
        }
        smsTask?.resume()
    }

    private func fetchSMSMessagesViaUFI(
        ufiBaseURL: String,
        candidateTokens: [String],
        generation: UInt,
        hasTriedSchemeSwap: Bool = false
    ) {
        guard generation == requestGeneration,
              let token = candidateTokens.first,
              let url = smsMessagesURL(baseURL: ufiBaseURL, isUFIProxy: true) else {
            finishSMSFetch(message: "短信接口地址无效", generation: generation)
            return
        }

        smsTask = session.dataTask(with: signedUFIRequest(url: url, token: token)) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }

                if let http = response as? HTTPURLResponse,
                   http.statusCode == 200,
                   let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   self.applySMSPayload(json) {
                    return
                } else if candidateTokens.count > 1 {
                    self.fetchSMSMessagesViaUFI(
                        ufiBaseURL: ufiBaseURL,
                        candidateTokens: Array(candidateTokens.dropFirst()),
                        generation: generation,
                        hasTriedSchemeSwap: hasTriedSchemeSwap
                    )
                } else if !hasTriedSchemeSwap,
                          let host = URL(string: ufiBaseURL)?.host,
                          !F50Configuration.isIPAddress(host) {
                    let targetScheme = ufiBaseURL.hasPrefix("https://") ? "http" : "https"
                    let portPart = URL(string: ufiBaseURL)?.port.map { ":\($0)" } ?? ""
                    let swappedURL = "\(targetScheme)://\(host)\(portPart)"
                    self.fetchSMSMessagesViaUFI(
                        ufiBaseURL: swappedURL,
                        candidateTokens: self.candidateTokens(),
                        generation: generation,
                        hasTriedSchemeSwap: true
                    )
                } else {
                    self.finishSMSFetch(
                        message: error?.localizedDescription ?? "无法读取短信，请检查 UFI 后台口令与短信权限",
                        generation: generation
                    )
                }
            }
        }
        smsTask?.resume()
    }

    @discardableResult
    private func applySMSPayload(_ json: [String: Any]) -> Bool {
        guard let messages = F50ResponseParser.parseSMSMessages(json) else { return false }
        let readIds = locallyReadSMSIds
        smsMessages = messages.map { message in
            var updated = message
            if readIds.contains(message.id) {
                updated.isLocallyRead = true
            }
            return updated
        }
        status.smsUnreadCount = smsMessages.filter { $0.isUnread }.count
        smsErrorMessage = nil
        isFetchingSMS = false
        smsTask = nil
        return true
    }

    private func finishSMSFetch(message: String, generation: UInt) {
        guard generation == requestGeneration else { return }
        smsErrorMessage = message
        isFetchingSMS = false
        smsTask = nil
    }

    // MARK: - 短信自动刷新与标记已读

    public func startSMSAutoRefresh(interval: TimeInterval = 4.0) {
        stopSMSAutoRefresh()
        fetchSMSMessages()
        smsAutoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchSMSMessages()
            }
        }
    }

    public func stopSMSAutoRefresh() {
        smsAutoRefreshTimer?.invalidate()
        smsAutoRefreshTimer = nil
    }

    public func markSMSAsRead(ids: [String]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            locallyReadSMSIds.insert(id)
        }
        UserDefaults.standard.set(Array(locallyReadSMSIds), forKey: "F50_LocallyReadSMSIds")

        let readIds = locallyReadSMSIds
        smsMessages = smsMessages.map { msg in
            var m = msg
            if readIds.contains(msg.id) {
                m.isLocallyRead = true
            }
            return m
        }
        status.smsUnreadCount = smsMessages.filter { $0.isUnread }.count
        if isDemoMode { return }

        // 同步设备端标记已读
        let cleanBase = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let ufiBaseURL = connectionEndpoints(from: cleanBase).ufiBaseURL
        let tokens = candidateTokens()
        guard let token = tokens.first else { return }

        let idsJoined = ids.joined(separator: ";") + ";"
        computeSMSADViaUFI(ufiBaseURL: ufiBaseURL, token: token, generation: requestGeneration) { [weak self] ad in
            guard let self else { return }
            let body = "isTest=false&goformId=SET_MSG_READ&msg_id=\(idsJoined)&tag=0&AD=\(ad)"
            guard let url = URL(string: "\(ufiBaseURL)/api/goform/goform_set_cmd_process"),
                  let bodyData = body.data(using: .utf8) else { return }

            var request = self.signedUFIRequest(
                url: url,
                token: token,
                method: "POST",
                body: bodyData,
                contentType: "application/x-www-form-urlencoded; charset=UTF-8"
            )
            request.timeoutInterval = 5.0
            self.session.dataTask(with: request).resume()
        }
    }

    public func markAllSMSAsRead() {
        let unreadIds = smsMessages.filter { $0.isUnread }.map { $0.id }
        markSMSAsRead(ids: unreadIds)
        status.smsUnreadCount = 0
    }

    // MARK: - 发送短信

    @Published public private(set) var isSendingSMS = false
    @Published public private(set) var smsSendErrorMessage: String?
    @Published public private(set) var smsSendSuccess = false

    public func sendSMSMessage(to number: String, content: String) {
        guard !isSendingSMS else { return }
        let cleanNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty, !cleanContent.isEmpty else {
            smsSendErrorMessage = "请填写手机号和短信内容"
            return
        }

        if isDemoMode {
            isSendingSMS = true
            smsSendErrorMessage = nil
            smsSendSuccess = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let newMsg = F50SMSMessage(
                    id: "demo-out-\(UUID().uuidString.prefix(6))",
                    number: cleanNumber,
                    content: cleanContent,
                    dateText: formatter.string(from: Date()),
                    tag: "2",
                    isLocallyRead: true
                )
                self.smsMessages.insert(newMsg, at: 0)
                self.finishSMSSent()
            }
            return
        }

        let generation = requestGeneration
        let cleanBase = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if let huaweiAdapter {
            isSendingSMS = true
            smsSendErrorMessage = nil
            smsSendSuccess = false
            Task { [weak self] in
                do {
                    try await huaweiAdapter.sendMessage(to: cleanNumber, content: cleanContent, password: self?.password ?? "")
                    guard let self, generation == self.requestGeneration else { return }
                    self.finishSMSSent()
                } catch {
                    guard let self, generation == self.requestGeneration else { return }
                    self.isSendingSMS = false
                    self.smsSendErrorMessage = "华为 HiLink: \(error.localizedDescription)"
                }
            }
            return
        }
        let endpoints = connectionEndpoints(from: cleanBase)
        let tokens = candidateTokens()

        isSendingSMS = true
        smsSendErrorMessage = nil
        smsSendSuccess = false

        attemptSendSMSViaRouter(
            routerBaseURL: endpoints.routerBaseURL,
            ufiBaseURL: endpoints.ufiBaseURL,
            candidateTokens: tokens,
            number: cleanNumber,
            content: cleanContent,
            generation: generation
        )
    }

    /// 短信发送与设备数据读取保持相同优先级：80 Router → 5555 ADB → 2333 UFI。
    private func attemptSendSMSViaRouter(
        routerBaseURL: String,
        ufiBaseURL: String,
        candidateTokens: [String],
        number: String,
        content: String,
        generation: UInt
    ) {
        sendSMSViaRouter(
            routerBaseURL: routerBaseURL,
            number: number,
            content: content,
            generation: generation
        ) { [weak self] routerSuccess in
            guard let self, generation == self.requestGeneration else { return }
            if routerSuccess {
                self.finishSMSSent()
                return
            }

            let host = URL(string: routerBaseURL)?.host ?? "192.168.0.1"
            Task { @MainActor in
                let adbSuccess = await self.sendSMSViaADB(
                    host: host,
                    number: number,
                    content: content,
                    generation: generation
                )
                guard generation == self.requestGeneration else { return }
                if adbSuccess {
                    self.finishSMSSent()
                } else {
                    self.attemptSendSMS(
                        ufiBaseURL: ufiBaseURL,
                        candidateTokens: candidateTokens,
                        number: number,
                        content: content,
                        generation: generation
                    )
                }
            }
        }
    }

    private func finishSMSSent() {
        smsSendSuccess = true
        smsSendErrorMessage = nil
        isSendingSMS = false
        fetchSMSMessages()
    }

    private func sendSMSViaRouter(
        routerBaseURL: String,
        number: String,
        content: String,
        generation: UInt,
        didLogin: Bool = false,
        completion: @escaping (Bool) -> Void
    ) {
        computeSMSADViaRouter(
            routerBaseURL: routerBaseURL,
            generation: generation
        ) { [weak self] ad in
            guard let self, generation == self.requestGeneration else { return }
            guard let ad,
                  let url = URL(string: "\(routerBaseURL)/goform/goform_set_cmd_process") else {
                self.retryRouterSMSSendAfterLogin(
                    routerBaseURL: routerBaseURL,
                    number: number,
                    content: content,
                    generation: generation,
                    didLogin: didLogin,
                    completion: completion
                )
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 5.0
            request.setValue("\(routerBaseURL)/index.html", forHTTPHeaderField: "Referer")
            request.setValue(
                "application/x-www-form-urlencoded; charset=UTF-8",
                forHTTPHeaderField: "Content-Type"
            )
            if let sessionCookie = self.sessionCookie, !sessionCookie.isEmpty {
                request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            }
            request.httpBody = F50ResponseParser.buildSMSRequestBody(
                number: number,
                content: content,
                ad: ad
            ).data(using: .utf8)

            self.session.dataTask(with: request) { [weak self] data, response, _ in
                guard let self else { return }
                Task { @MainActor in
                    guard generation == self.requestGeneration else { return }
                    if let http = response as? HTTPURLResponse,
                       http.statusCode == 200,
                       let data,
                       self.isSMSSendSuccess(data) {
                        completion(true)
                    } else {
                        self.retryRouterSMSSendAfterLogin(
                            routerBaseURL: routerBaseURL,
                            number: number,
                            content: content,
                            generation: generation,
                            didLogin: didLogin,
                            completion: completion
                        )
                    }
                }
            }.resume()
        }
    }

    private func retryRouterSMSSendAfterLogin(
        routerBaseURL: String,
        number: String,
        content: String,
        generation: UInt,
        didLogin: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard !didLogin else {
            completion(false)
            return
        }
        performZTELogin(hostOnly: routerBaseURL) { [weak self] loginSuccess in
            guard let self, generation == self.requestGeneration else { return }
            guard loginSuccess else {
                completion(false)
                return
            }
            self.sendSMSViaRouter(
                routerBaseURL: routerBaseURL,
                number: number,
                content: content,
                generation: generation,
                didLogin: true,
                completion: completion
            )
        }
    }

    private func computeSMSADViaRouter(
        routerBaseURL: String,
        generation: UInt,
        completion: @escaping (String?) -> Void
    ) {
        let ts = String(Int64(Date().timeIntervalSince1970 * 1000))
        guard let versionURL = URL(
            string: "\(routerBaseURL)/goform/goform_get_cmd_process?cmd=Language,cr_version,wa_inner_version&multi_data=1&isTest=false&_=\(ts)"
        ) else {
            completion(nil)
            return
        }
        var versionRequest = URLRequest(url: versionURL)
        versionRequest.timeoutInterval = 4.0
        versionRequest.setValue("\(routerBaseURL)/index.html", forHTTPHeaderField: "Referer")
        if let sessionCookie, !sessionCookie.isEmpty {
            versionRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        session.dataTask(with: versionRequest) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration,
                      let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      let data,
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(nil)
                    return
                }
                let wa = (dict["wa_inner_version"] as? String) ?? (dict["wa_version"] as? String) ?? ""
                let cr = (dict["cr_version"] as? String) ?? ""
                let ts2 = String(Int64(Date().timeIntervalSince1970 * 1000))
                guard let rdURL = URL(
                    string: "\(routerBaseURL)/goform/goform_get_cmd_process?cmd=RD&isTest=false&_=\(ts2)"
                ) else {
                    completion(nil)
                    return
                }
                var rdRequest = URLRequest(url: rdURL)
                rdRequest.timeoutInterval = 4.0
                rdRequest.setValue("\(routerBaseURL)/index.html", forHTTPHeaderField: "Referer")
                if let sessionCookie = self.sessionCookie, !sessionCookie.isEmpty {
                    rdRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                }
                self.session.dataTask(with: rdRequest) { [weak self] data, response, _ in
                    guard let self else { return }
                    Task { @MainActor in
                        guard generation == self.requestGeneration,
                              let http = response as? HTTPURLResponse,
                              http.statusCode == 200,
                              let data,
                              let rdDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            completion(nil)
                            return
                        }
                        let rd = (rdDict["RD"] as? String) ?? ""
                        completion(self.sha256(self.sha256(wa + cr) + rd).uppercased())
                    }
                }.resume()
            }
        }.resume()
    }

    private func sendSMSViaADB(
        host: String,
        number: String,
        content: String,
        generation: UInt
    ) async -> Bool {
        guard generation == requestGeneration,
              let output = await ADBHardwareFetcher.executeShell(
                host: host,
                port: 5555,
                command: smsShellCommand(number: number, content: content),
                timeoutSec: 8.0
              ) else {
            return false
        }
        return output.contains("Result: Parcel") && !output.contains("Exception")
    }

    private func smsShellCommand(number: String, content: String) -> String {
        let cleanNum = number.components(
            separatedBy: CharacterSet(charactersIn: "0123456789+").inverted
        ).joined()
        let b64Body = Data(content.utf8).base64EncodedString()
        return """
        sub_id=$(content query --uri content://telephony/siminfo --projection _id --where "sim_id>=0" 2>/dev/null | grep -o "_id=[0-9]*" | head -n 1 | cut -d= -f2)
        if [ -z "$sub_id" ]; then sub_id=3; fi
        BODY=$(echo "\(b64Body)" | base64 -d)
        service call isms 6 i32 $sub_id s16 "com.android.phone" s16 "null" s16 "\(cleanNum)" s16 "null" s16 "$BODY" s16 "null" s16 "null" i32 1 || \
        service call isms 7 i32 $sub_id s16 "com.android.phone" s16 "null" s16 "\(cleanNum)" s16 "null" s16 "$BODY" s16 "null" s16 "null" i32 1 || \
        service call isms 5 i32 $sub_id s16 "com.android.phone" s16 "null" s16 "\(cleanNum)" s16 "null" s16 "$BODY" s16 "null" s16 "null" i32 1
        """
    }

    private func isSMSSendSuccess(_ data: Data) -> Bool {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let resultInt = dict["result"] as? Int
            let resultStr = (dict["result"] as? String)?.lowercased()
            return resultInt == 0 || resultInt == 3
                || resultStr == "0" || resultStr == "3" || resultStr == "success"
        }
        guard let raw = String(data: data, encoding: .utf8) else { return false }
        return raw.contains("\"result\":0")
            || raw.contains("\"result\":\"0\"")
            || raw.lowercased().contains("success")
    }

    private func attemptSendSMS(
        ufiBaseURL: String,
        candidateTokens: [String],
        number: String,
        content: String,
        generation: UInt
    ) {
        guard generation == requestGeneration, let token = candidateTokens.first else {
            finishSMSFailed("发送失败，请检查 UFI后台口令与管理密码")
            return
        }

        // 策略 1：通过 MiniKano /api/root_shell 底层 Telephony service call isms 6 直接发信（已实测验证）
        sendSMSViaRootShell(
            ufiBaseURL: ufiBaseURL,
            token: token,
            number: number,
            content: content,
            generation: generation
        ) { [weak self] shellSuccess in
            guard let self, generation == self.requestGeneration else { return }
            if shellSuccess {
                self.finishSMSSent()
            } else {
                // 策略 2：通过 /api/goform/goform_set_cmd_process 标准接口发送
                self.sendSMSViaGoform(
                    ufiBaseURL: ufiBaseURL,
                    token: token,
                    number: number,
                    content: content,
                    generation: generation
                ) { [weak self] goformSuccess, errMsg in
                    guard let self, generation == self.requestGeneration else { return }
                    if goformSuccess {
                        self.finishSMSSent()
                    } else if candidateTokens.count > 1 {
                        self.attemptSendSMS(
                            ufiBaseURL: ufiBaseURL,
                            candidateTokens: Array(candidateTokens.dropFirst()),
                            number: number,
                            content: content,
                            generation: generation
                        )
                    } else {
                        self.finishSMSFailed(errMsg ?? "发送失败，请检查 SIM 卡状态或后台权限")
                    }
                }
            }
        }
    }

    /// 策略 1：/api/root_shell Android 底层短信调用
    private func sendSMSViaRootShell(
        ufiBaseURL: String,
        token: String,
        number: String,
        content: String,
        generation: UInt,
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(ufiBaseURL)/api/root_shell") else {
            completion(false)
            return
        }

        let cmd = smsShellCommand(number: number, content: content)

        let bodyObj: [String: Any] = ["command": cmd]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyObj, options: []) else {
            completion(false)
            return
        }

        var request = signedUFIRequest(url: url, token: token, method: "POST", body: body)
        request.timeoutInterval = 8.0

        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(false)
                    return
                }

                let rawResult: String
                if let dictRes = json["result"] as? [String: Any], let c = dictRes["content"] as? String {
                    rawResult = c
                } else if let strRes = json["result"] as? String {
                    rawResult = strRes
                } else {
                    rawResult = ""
                }

                if rawResult.contains("Result: Parcel") && !rawResult.contains("Exception") {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }

    /// 策略 2：goform_set_cmd_process 发送短信（先获取 wa/cr/RD 计算 AD 鉴权参数）
    private func sendSMSViaGoform(
        ufiBaseURL: String,
        token: String,
        number: String,
        content: String,
        generation: UInt,
        completion: @escaping (Bool, String?) -> Void
    ) {
        computeSMSADViaUFI(ufiBaseURL: ufiBaseURL, token: token, generation: generation) { [weak self] ad in
            guard let self, generation == self.requestGeneration else { return }
            let bodyString = F50ResponseParser.buildSMSRequestBody(
                number: number,
                content: content,
                ad: ad
            )
            guard let url = URL(string: "\(ufiBaseURL)/api/goform/goform_set_cmd_process"),
                  let body = bodyString.data(using: .utf8) else {
                completion(false, "短信接口地址无效")
                return
            }

            var request = self.signedUFIRequest(
                url: url,
                token: token,
                method: "POST",
                body: body,
                contentType: "application/x-www-form-urlencoded; charset=UTF-8"
            )
            request.timeoutInterval = 10.0

            self.session.dataTask(with: request) { [weak self] data, response, _ in
                guard let self else { return }
                Task { @MainActor in
                    guard generation == self.requestGeneration else { return }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          let data else {
                        completion(false, nil)
                        return
                    }

                    if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let resultInt = dict["result"] as? Int
                        let resultStr = (dict["result"] as? String)?.lowercased()
                        if resultInt == 0 || resultInt == 3 || resultStr == "0" || resultStr == "3" || resultStr == "success" {
                            completion(true, nil)
                        } else if resultStr == "sms_send_failed" || resultInt == 1 || resultStr == "1" {
                            completion(false, "发送失败（请检查 SIM 卡状态或短信配额）")
                        } else if let res = dict["result"] {
                            completion(false, "发送失败：\(res)")
                        } else {
                            let raw = String(data: data, encoding: .utf8) ?? ""
                            completion(false, raw.isEmpty ? nil : "发送失败：\(raw)")
                        }
                    } else if let raw = String(data: data, encoding: .utf8),
                              (raw.contains("\"result\":0") || raw.contains("\"result\":\"0\"") || raw.contains("success")) {
                        completion(true, nil)
                    } else {
                        completion(false, nil)
                    }
                }
            }.resume()
        }
    }

    private func computeSMSADViaUFI(
        ufiBaseURL: String,
        token: String,
        generation: UInt,
        completion: @escaping (String) -> Void
    ) {
        let ts = String(Int64(Date().timeIntervalSince1970 * 1000))
        guard let url = URL(string: "\(ufiBaseURL)/api/goform/goform_get_cmd_process?cmd=Language,cr_version,wa_inner_version&multi_data=1&isTest=false&_=\(ts)") else {
            completion("")
            return
        }

        session.dataTask(with: signedUFIRequest(url: url, token: token)) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data,
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion("")
                    return
                }

                let wa = (dict["wa_inner_version"] as? String) ?? (dict["wa_version"] as? String) ?? ""
                let cr = (dict["cr_version"] as? String) ?? ""

                let ts2 = String(Int64(Date().timeIntervalSince1970 * 1000))
                guard let rdURL = URL(string: "\(ufiBaseURL)/api/goform/goform_get_cmd_process?cmd=RD&isTest=false&_=\(ts2)") else {
                    let ad = self.sha256(self.sha256(wa + cr)).uppercased()
                    completion(ad)
                    return
                }

                self.session.dataTask(with: self.signedUFIRequest(url: rdURL, token: token)) { [weak self] data, response, _ in
                    guard let self else { return }
                    Task { @MainActor in
                        guard generation == self.requestGeneration else { return }
                        let rdDict = (data != nil) ? (try? JSONSerialization.jsonObject(with: data!) as? [String: Any]) : nil
                        let rd = (rdDict?["RD"] as? String) ?? ""
                        let ad = self.sha256(self.sha256(wa + cr) + rd).uppercased()
                        completion(ad)
                    }
                }.resume()
            }
        }.resume()
    }

    private func finishSMSFailed(_ message: String) {
        guard !smsSendSuccess else { return }
        smsSendErrorMessage = message
        isSendingSMS = false
    }

    private func connectionEndpoints(from cleanBase: String) -> (routerBaseURL: String, ufiBaseURL: String) {
        F50Configuration.resolveEndpoints(from: cleanBase)
    }

    private func handleRouterFailure(
        _ message: String,
        ufiBaseURL: String,
        generation: UInt,
        refreshTraffic: Bool,
        allowsUFIFallback: Bool
    ) {
        guard allowsUFIFallback else {
            updateStatusFailed(message, generation: generation)
            return
        }
        let hostOnly = routerBaseURL(from: ufiBaseURL)
        let host = URL(string: hostOnly)?.host ?? "192.168.0.1"
        Task { @MainActor in
            await self.applyADBMetrics(host: host, primaryPayload: nil)
            guard generation == self.requestGeneration else { return }
            self.executeUFIFetch(
                cleanBase: hostOnly,
                hostOnly: hostOnly,
                ufiBaseURL: ufiBaseURL,
                generation: generation,
                refreshTraffic: refreshTraffic,
                didTryADB: true
            )
        }
    }

    private func executeUFIFetch(
        cleanBase: String,
        hostOnly: String,
        ufiBaseURL: String,
        generation: UInt,
        refreshTraffic: Bool,
        candidateTokens: [String]? = nil,
        hasTriedSchemeSwap: Bool = false,
        didTryADB: Bool = false
    ) {
        guard generation == requestGeneration else { return }
        let tokens = candidateTokens ?? self.candidateTokens()
        guard let token = tokens.first,
              let url = URL(string: "\(ufiBaseURL)/api/baseDeviceInfo") else {
            updateStatusFailed("UFI API 地址无效", generation: generation)
            return
        }

        baseTask = session.dataTask(with: signedUFIRequest(url: url, token: token)) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }

                if let http = response as? HTTPURLResponse,
                   http.statusCode == 200,
                   let data,
                   let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.fetchUFISignalPayload(
                        ufiBaseURL: ufiBaseURL,
                        token: token,
                        generation: generation
                    ) { signalPayload in
                        var merged: [String: Any] = [:]
                        if let dataDict = payload["data"] as? [String: Any] {
                            dataDict.forEach { merged[$0.key] = $0.value }
                        }
                        if let resDict = payload["result"] as? [String: Any] {
                            resDict.forEach { merged[$0.key] = $0.value }
                        }
                        payload.forEach {
                            if $0.key != "data" && $0.key != "result" {
                                merged[$0.key] = $0.value
                            }
                        }

                        if let signalPayload {
                            if let dataDict = signalPayload["data"] as? [String: Any] {
                                dataDict.forEach { merged[$0.key] = $0.value }
                            }
                            if let resDict = signalPayload["result"] as? [String: Any] {
                                resDict.forEach { merged[$0.key] = $0.value }
                            }
                            signalPayload.forEach {
                                if $0.key != "data" && $0.key != "result" {
                                    merged[$0.key] = $0.value
                                }
                            }
                        }

                        merged = F50ResponseParser.normalizeUFIPayload(merged)
                        guard generation == self.requestGeneration else { return }
                        let adbQci = didTryADB ? self.status.qci : ""
                        let adbQosDl = didTryADB ? self.status.qosDl : ""
                        let adbQosUl = didTryADB ? self.status.qosUl : ""
                        let adbCPU = didTryADB ? self.status.cpuUsage : 0
                        let adbMemory = didTryADB ? self.status.memUsage : 0
                        let adbTemperature = didTryADB ? self.status.temperature : 0
                        self.parseStatusDict(merged, preserveQos: true, refreshTraffic: refreshTraffic)
                        self.diagnosticChannelMode = "2333 UFI"
                        self.appendLog("降级", "2333 UFI 状态读取成功")
                        if !adbQci.isEmpty { self.status.qci = adbQci }
                        if !adbQosDl.isEmpty { self.status.qosDl = adbQosDl }
                        if !adbQosUl.isEmpty { self.status.qosUl = adbQosUl }
                        if adbCPU > 0 { self.status.cpuUsage = adbCPU }
                        if adbMemory > 0 { self.status.memUsage = adbMemory }
                        if adbTemperature > 0 { self.status.temperature = adbTemperature }
                        if refreshTraffic {
                            self.lastTrafficRefreshDate = Date()
                        }
                        self.isFetching = false
                        self.fetchHardwareAndExtensionMetrics(
                            hostOnly: hostOnly,
                            ufiBaseURL: ufiBaseURL,
                            generation: generation,
                            refreshTraffic: refreshTraffic,
                            primaryPayload: merged,
                            skipADB: didTryADB,
                            routerAvailable: false
                        )
                    }
                } else if tokens.count > 1,
                          let http = response as? HTTPURLResponse,
                          (http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 400) {
                    // 鉴权/接口报错：尝试下一个候选 token
                    self.executeUFIFetch(
                        cleanBase: cleanBase,
                        hostOnly: hostOnly,
                        ufiBaseURL: ufiBaseURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        candidateTokens: Array(tokens.dropFirst()),
                        hasTriedSchemeSwap: hasTriedSchemeSwap,
                        didTryADB: didTryADB
                    )
                } else if !hasTriedSchemeSwap,
                          let host = URL(string: ufiBaseURL)?.host,
                          !F50Configuration.isIPAddress(host) {
                    // 如果是域名访问且当前协议未连通（如 http 连不上改试 https，或反之），自动尝试切换协议
                    let targetScheme = ufiBaseURL.hasPrefix("https://") ? "http" : "https"
                    let portPart = URL(string: ufiBaseURL)?.port.map { ":\($0)" } ?? ""
                    let swappedURL = "\(targetScheme)://\(host)\(portPart)"
                    self.executeUFIFetch(
                        cleanBase: swappedURL,
                        hostOnly: swappedURL,
                        ufiBaseURL: swappedURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        candidateTokens: nil,
                        hasTriedSchemeSwap: true,
                        didTryADB: didTryADB
                    )
                } else {
                    let errorMsg = error?.localizedDescription ?? (response.map { "HTTP \((($0 as? HTTPURLResponse)?.statusCode ?? 0))" } ?? "无法连接设备 UFI 后台")
                    self.updateStatusFailed(errorMsg, generation: generation)
                }
            }
        }
        baseTask?.resume()
    }

    private func fetchUFISignalPayload(
        ufiBaseURL: String,
        token: String,
        generation: UInt,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        // 注意：F50 固件会把“显式请求的 nr_rsrp/nr_rsrq/Nr_snr/nr_snr”对应的
        // network_information dump 字段清零（返回空串）。因此这里绝不显式请求这
        // 四个命令，信号值统一由 network_information 的 dump（nr_rsrp/nr_rsrq/Nr_snr）
        // 提供，Z5g_rsrp 作为独立数据源保留作 RSRP 兑底。
        let commands = "network_type,network_provider,signalbar,network_signalbar,network_information,Z5g_rsrp,Z5g_rsrq,Z5g_snr,5g_rsrp,5g_rsrq,5g_snr,lte_rsrp,lte_rsrq,lte_snr,wifi_access_sta_num,sms_unread_num,sms_sim_unread_num,wan_active_band,lte_band,lte_ca_pcell_band,nr5g_action_band,nr5g_action_nsa_band,ZCELLINFO_band,Z5g_CELLINFO_band,nr_ca_pcell_band,data_volume_limit_size,data_volume_limit_unit,data_volume_limit_switch,flux_data_volume_limit_size,flux_data_volume_limit_switch,data_volume_clear_day,monthly_clear_day,clear_day,data_volume_reset_day,billing_day,clear_date,reset_day,traffic_clear_date,flux_clear_date,realtime_rx_thrpt,realtime_tx_thrpt,realtime_rx_bytes,realtime_tx_bytes,monthly_rx_bytes,monthly_tx_bytes,total_rx_bytes,total_tx_bytes,temperature,cpu_temp,internal_temperature,ic_temp,cpu_utility,mem_utility,qci"
        // 注意：minikano goform 要求 cmd 参数放在第一位，否则最后一个字段名会被拼坏
        guard let url = URL(string: "\(ufiBaseURL)/api/goform/goform_get_cmd_process?cmd=\(commands)&is_all=true") else {
            completion(nil)
            return
        }

        session.dataTask(with: signedUFIRequest(url: url, token: token)) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                if let http = response as? HTTPURLResponse,
                   http.statusCode == 200,
                   let data,
                   let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   !payload.isEmpty, payload["Error"] == nil {
                    completion(payload)
                } else {
                    // 如果 /api/goform 在该 UFI 版本未开启或失败，尝试回退到 /api/signalDeviceInfo
                    self.fetchUFISignalDeviceInfo(ufiBaseURL: ufiBaseURL, token: token, generation: generation, completion: completion)
                }
            }
        }.resume()
    }

    private func fetchUFISignalDeviceInfo(
        ufiBaseURL: String,
        token: String,
        generation: UInt,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        guard let url = URL(string: "\(ufiBaseURL)/api/signalDeviceInfo") else {
            completion(nil)
            return
        }
        session.dataTask(with: signedUFIRequest(url: url, token: token)) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(nil)
                    return
                }
                let payload = (json["data"] as? [String: Any]) ?? (json["result"] as? [String: Any]) ?? json
                completion(payload)
            }
        }.resume()
    }

    /// 构建带 UFI-TOOLS 签名头部的请求（GET/POST 统一入口）
    private func signedUFIRequest(
        url: URL,
        token: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json"
    ) -> URLRequest {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let sign = calcKanoSign(
            key: F50Configuration.kanoSignKey,
            data: "minikano\(method)\(url.path)\(timestamp)"
        )
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 4.0
        request.setValue(timestamp, forHTTPHeaderField: "kano-t")
        request.setValue(sign, forHTTPHeaderField: "kano-sign")
        request.setValue(token, forHTTPHeaderField: "authorization")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let scheme = url.scheme, let host = url.host {
            let portPart = url.port.map { ":\($0)" } ?? ""
            let origin = "\(scheme)://\(host)\(portPart)"
            request.setValue(origin, forHTTPHeaderField: "Origin")
            request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        }
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func executeFetch(
        cleanBase: String,
        hostOnly: String,
        ufiBaseURL: String,
        generation: UInt,
        refreshTraffic: Bool,
        isRetryAfterLogin: Bool = false,
        allowsUFIFallback: Bool
    ) {
        // 信号指标（nr_rsrp/nr_rsrq/Nr_snr）由 network_information 的 dump 提供：
        // F50 固件若在列表中显式请求这四个命令，会把 dump 对应字段清零（返回空串），
        // 所以这里不显式请求它们，只保留独立数据源 Z5g_rsrp 与其它兑底字段。
        // V50 (MU3351) 会通过 temperature / cpu_temp 返回硬件指标；保留 ic_temp
        // 以兼容 F50 等旧固件。
        let statusCommands = "usb_port_switch,battery_charging,sms_received_flag,sms_unread_num,sms_sim_unread_num,sim_msisdn,battery_value,battery_vol_percent,network_signalbar,network_rssi,cr_version,iccid,imei,imsi,ipv6_wan_ipaddr,lan_ipaddr,mac_address,msisdn,network_information,Lte_ca_status,rssi,Z5g_rsrp,Z5g_snr,lte_rsrp,wifi_access_sta_num,loginfo,realtime_rx_thrpt,realtime_tx_thrpt,network_type,network_provider,ppp_status,temperature,cpu_temp,internal_temperature,ic_temp,cpu_utility,mem_utility,5g_rsrp,5g_rsrq,5g_snr,lte_rsrq,lte_snr,signalbar,qci,ambr,dl_ambr,ul_ambr"
        let trafficCommands = "realtime_rx_bytes,realtime_tx_bytes,realtime_time,monthly_tx_bytes,monthly_rx_bytes,monthly_time,day_rx_bytes,day_tx_bytes,total_rx_bytes,total_tx_bytes,data_volume_limit_size,data_volume_limit_unit,data_volume_limit_switch,data_volume_clear_date,monthly_clear_date,clear_date,data_volume_clear_day,monthly_clear_day,clear_day,data_volume_reset_day,billing_day,traffic_clear_date"
        let cmdList = refreshTraffic ? "\(statusCommands),\(trafficCommands)" : statusCommands

        let targetURLString = "\(hostOnly)/goform/goform_get_cmd_process?multi_data=1&isTest=false&cmd=\(cmdList)"

        guard let url = URL(string: targetURLString) else {
            handleRouterFailure(
                "无效的 URL",
                ufiBaseURL: ufiBaseURL,
                generation: generation,
                refreshTraffic: refreshTraffic,
                allowsUFIFallback: allowsUFIFallback
            )
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0
        request.setValue("\(hostOnly)/index.html", forHTTPHeaderField: "Referer")

        if let cookie = sessionCookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        baseTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }

                if let error = error {
                    self.handleRouterFailure(
                        error.localizedDescription,
                        ufiBaseURL: ufiBaseURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        allowsUFIFallback: allowsUFIFallback
                    )
                    return
                }

                guard let httpRes = response as? HTTPURLResponse else {
                    self.handleRouterFailure(
                        "网络响应错误",
                        ufiBaseURL: ufiBaseURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        allowsUFIFallback: allowsUFIFallback
                    )
                    return
                }

                if (httpRes.statusCode == 401 || httpRes.statusCode == 403) && !isRetryAfterLogin {
                    self.retryRouterAfterLogin(
                        reason: "HTTP \(httpRes.statusCode)",
                        cleanBase: cleanBase,
                        hostOnly: hostOnly,
                        ufiBaseURL: ufiBaseURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        allowsUFIFallback: allowsUFIFallback
                    )
                    return
                }

                guard httpRes.statusCode == 200, let data = data else {
                    self.handleRouterFailure(
                        "HTTP 错误: \(httpRes.statusCode)",
                        ufiBaseURL: ufiBaseURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        allowsUFIFallback: allowsUFIFallback
                    )
                    return
                }

                do {
                    if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        // 设备可能返回 {"Error":"none secure connection"} 等未认证/异常响应（HTTP 仍为 200）
                        if let errorText = dict["Error"] as? String, !errorText.isEmpty {
                            if !isRetryAfterLogin {
                                self.retryRouterAfterLogin(
                                    reason: errorText,
                                    cleanBase: cleanBase,
                                    hostOnly: hostOnly,
                                    ufiBaseURL: ufiBaseURL,
                                    generation: generation,
                                    refreshTraffic: refreshTraffic,
                                    allowsUFIFallback: allowsUFIFallback
                                )
                            } else {
                                self.handleRouterFailure(
                                    "设备返回错误: \(errorText)",
                                    ufiBaseURL: ufiBaseURL,
                                    generation: generation,
                                    refreshTraffic: refreshTraffic,
                                    allowsUFIFallback: allowsUFIFallback
                                )
                            }
                            return
                        }

                        guard F50ResponseParser.isRouterStatusPayload(dict) else {
                            if !isRetryAfterLogin {
                                self.retryRouterAfterLogin(
                                    reason: "未返回状态字段",
                                    cleanBase: cleanBase,
                                    hostOnly: hostOnly,
                                    ufiBaseURL: ufiBaseURL,
                                    generation: generation,
                                    refreshTraffic: refreshTraffic,
                                    allowsUFIFallback: allowsUFIFallback
                                )
                            } else {
                                self.handleRouterFailure(
                                    "设备未返回有效状态字段",
                                    ufiBaseURL: ufiBaseURL,
                                    generation: generation,
                                    refreshTraffic: refreshTraffic,
                                    allowsUFIFallback: allowsUFIFallback
                                )
                            }
                            return
                        }

                        self.parseStatusDict(
                            dict,
                            preserveQos: true,
                            refreshTraffic: refreshTraffic
                        )
                        self.diagnosticChannelMode = "80 Router"
                        self.appendLog("连接", "80 Router 状态读取成功")
                        if refreshTraffic {
                            self.lastTrafficRefreshDate = Date()
                        }
                        self.isFetching = false
                        self.fetchBandMetrics(hostOnly: hostOnly, generation: generation)
                        self.fetchHardwareAndExtensionMetrics(
                            hostOnly: hostOnly,
                            ufiBaseURL: ufiBaseURL,
                            generation: generation,
                            refreshTraffic: refreshTraffic,
                            primaryPayload: dict,
                            skipADB: false,
                            routerAvailable: true
                        )
                        if F50ResponseParser.requiresUFISupplement(dict) {
                            self.fetchUFISupplement(
                                ufiBaseURL: ufiBaseURL,
                                routerPayload: dict,
                                candidateTokens: self.candidateTokens(),
                                generation: generation,
                                refreshTraffic: refreshTraffic
                            )
                        }
                    } else {
                        self.handleRouterFailure(
                            "解析 JSON 失败",
                            ufiBaseURL: ufiBaseURL,
                            generation: generation,
                            refreshTraffic: refreshTraffic,
                            allowsUFIFallback: allowsUFIFallback
                        )
                    }
                } catch {
                    self.handleRouterFailure(
                        error.localizedDescription,
                        ufiBaseURL: ufiBaseURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        allowsUFIFallback: allowsUFIFallback
                    )
                }
            }
        }
        baseTask?.resume()
    }

    private func retryRouterAfterLogin(
        reason: String,
        cleanBase: String,
        hostOnly: String,
        ufiBaseURL: String,
        generation: UInt,
        refreshTraffic: Bool,
        allowsUFIFallback: Bool
    ) {
        clearRouterSession(hostOnly: hostOnly)
        performZTELogin(hostOnly: hostOnly) { [weak self] success in
            guard let self, generation == self.requestGeneration else { return }
            if success {
                self.executeFetch(
                    cleanBase: cleanBase,
                    hostOnly: hostOnly,
                    ufiBaseURL: ufiBaseURL,
                    generation: generation,
                    refreshTraffic: refreshTraffic,
                    isRetryAfterLogin: true,
                    allowsUFIFallback: allowsUFIFallback
                )
            } else {
                self.handleRouterFailure(
                    "设备登录失败: \(reason)",
                    ufiBaseURL: ufiBaseURL,
                    generation: generation,
                    refreshTraffic: refreshTraffic,
                    allowsUFIFallback: allowsUFIFallback
                )
            }
        }
    }

    private func clearRouterSession(hostOnly: String) {
        sessionCookie = nil
        guard let url = URL(string: hostOnly) else { return }
        let storage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        storage.cookies(for: url)?.forEach(storage.deleteCookie)
    }

    private func fetchUFISupplement(
        ufiBaseURL: String,
        routerPayload: [String: Any],
        candidateTokens: [String],
        generation: UInt,
        refreshTraffic: Bool
    ) {
        guard generation == requestGeneration,
              !isFetchingUFISupplement,
              !candidateTokens.isEmpty else { return }
        isFetchingUFISupplement = true
        fetchUFISupplementAttempt(
            ufiBaseURL: ufiBaseURL,
            routerPayload: routerPayload,
            candidateTokens: candidateTokens,
            generation: generation,
            refreshTraffic: refreshTraffic
        )
    }

    private func fetchUFISupplementAttempt(
        ufiBaseURL: String,
        routerPayload: [String: Any],
        candidateTokens: [String],
        generation: UInt,
        refreshTraffic: Bool
    ) {
        guard generation == requestGeneration, let token = candidateTokens.first else {
            isFetchingUFISupplement = false
            return
        }

        fetchUFISignalPayload(
            ufiBaseURL: ufiBaseURL,
            token: token,
            generation: generation
        ) { [weak self] signalPayload in
            guard let self, generation == self.requestGeneration else { return }
            guard let signalPayload else {
                self.fetchUFISupplementAttempt(
                    ufiBaseURL: ufiBaseURL,
                    routerPayload: routerPayload,
                    candidateTokens: Array(candidateTokens.dropFirst()),
                    generation: generation,
                    refreshTraffic: refreshTraffic
                )
                return
            }

            var merged = routerPayload
            if let data = signalPayload["data"] as? [String: Any] {
                data.forEach { merged[$0.key] = $0.value }
            }
            if let result = signalPayload["result"] as? [String: Any] {
                result.forEach { merged[$0.key] = $0.value }
            }
            signalPayload.forEach {
                if $0.key != "data" && $0.key != "result" {
                    merged[$0.key] = $0.value
                }
            }

            self.parseStatusDict(
                F50ResponseParser.normalizeUFIPayload(merged),
                preserveQos: true,
                refreshTraffic: refreshTraffic
            )
            if !self.diagnosticChannelMode.contains("2333 UFI") {
                self.diagnosticChannelMode += " + 2333 UFI"
            }
            self.appendLog("补充", "2333 UFI 补齐 Router 缺失状态")
            self.isFetchingUFISupplement = false
        }
    }

    private func configurationDidChange() {
        requestGeneration &+= 1
        baseTask?.cancel()
        bandTask?.cancel()
        shellTask?.cancel()
        qosTask?.cancel()
        packageTask?.cancel()
        smsTask?.cancel()
        baseTask = nil
        bandTask = nil
        shellTask = nil
        qosTask = nil
        packageTask = nil
        smsTask = nil
        isFetching = false
        isFetchingExtensions = false
        isFetchingUFISupplement = false
        isFetchingSMS = false
        smsMessages = []
        smsErrorMessage = nil
        sessionCookie = nil
        huaweiAdapter = nil
        hasProbedHuawei = false
        cachedCandidateTokens = nil
        cachedTokenSource = ""
        diagnosticFirmwareVersion = ""
        diagnosticChannelMode = "未知"
        status.qci = ""
        status.qosDl = ""
        status.qosUl = ""
        status.clearHardwareMetrics()
        // 重置独立流量字段：避免新配置下短暂显示旧设备的流量
        status.ufiDailyUsage = 0
        status.ufiMonthlyUsage = 0
        status.packageRx = 0
        status.packageTx = 0
        status.monthlyRx = 0
        status.monthlyTx = 0
        status.trafficLimit = 0
        prevTotalCpu = 0
        prevIdleCpu = 0
        lastTrafficRefreshDate = .distantPast
        lastADBHardwareRefreshDate = .distantPast
        lastADBQosRefreshDate = .distantPast
    }

    /// 优先级体系：
    /// 1. 80 端口（中兴 Router 后台）为主数据通道（信号、速率、流量、频段等）。
    /// 2. 5555 端口（ADB 原生 Socket）优先获取底层硬件指标（CPU 占用、内存占用、芯片温度）。
    /// 3. 2333 端口（UFI / MiniKano 工具箱）作为硬件指标与 QCI 的兜底/补充通道。
    private func fetchHardwareAndExtensionMetrics(
        hostOnly: String,
        ufiBaseURL: String,
        generation: UInt,
        refreshTraffic: Bool,
        primaryPayload: [String: Any]?,
        skipADB: Bool,
        routerAvailable: Bool
    ) {
        guard !isFetchingExtensions else { return }
        isFetchingExtensions = true

        let host = URL(string: hostOnly)?.host ?? "192.168.0.1"
        Task { @MainActor in
            guard generation == self.requestGeneration else { return }

            if !skipADB {
                await self.applyADBMetrics(host: host, primaryPayload: primaryPayload)
            }
            guard generation == self.requestGeneration else { return }

            // 仅对 80 与 5555 均未取得的数据调用 UFI。
            let needsQos = self.status.qci.isEmpty
                || self.status.qosDl.isEmpty
                || self.status.qosUl.isEmpty
            let needsHardware = self.status.cpuUsage <= 0
                || self.status.memUsage <= 0
                || self.status.temperature <= 0
            let needsUFFICellularUsage = refreshTraffic
                && (self.status.dailyRx + self.status.dailyTx == 0
                    || self.status.monthlyRx + self.status.monthlyTx == 0)
            let needsRouterPackageUsage = refreshTraffic && routerAvailable
            let requestCount = (needsQos ? 1 : 0)
                + (needsHardware ? 1 : 0)
                + (needsUFFICellularUsage ? 1 : 0)
                + (needsRouterPackageUsage ? 1 : 0)

            guard requestCount > 0 else {
                self.isFetchingExtensions = false
                return
            }

            let tokens = self.candidateTokens()
            self.pendingExtensionRequests = requestCount
            if needsQos {
                self.fetchQosMetrics(ufiBaseURL: ufiBaseURL, candidateTokens: tokens, generation: generation)
            }
            if needsHardware {
                self.fetchLinuxShellMetrics(ufiBaseURL: ufiBaseURL, candidateTokens: tokens, generation: generation)
            }
            if needsUFFICellularUsage {
                self.fetchCellularUsageMetrics(ufiBaseURL: ufiBaseURL, candidateTokens: tokens, generation: generation)
            }
            if needsRouterPackageUsage {
                self.fetchPackageUsageMetrics(routerBaseURL: hostOnly, generation: generation)
            }
        }
    }

    /// 将 5555 结果只写入 80 端口本轮未提供的字段，保证来源优先级不反转。
    private func applyADBMetrics(host: String, primaryPayload: [String: Any]?) async {
        var primaryStatus = F50Status()
        if let primaryPayload {
            primaryStatus.mergeHardwareMetrics(from: primaryPayload)
        }

        let now = Date()
        let needsHardware = (primaryStatus.cpuUsage <= 0
            || primaryStatus.memUsage <= 0
            || primaryStatus.temperature <= 0)
            && now.timeIntervalSince(lastADBHardwareRefreshDate) >= adbHardwareRefreshInterval
        let needsQos = (primaryStatus.qci.isEmpty
            || primaryStatus.qosDl.isEmpty
            || primaryStatus.qosUl.isEmpty)
            && now.timeIntervalSince(lastADBQosRefreshDate) >= adbQosRefreshInterval

        guard needsHardware || needsQos else { return }

        // 全部使用 shell 内建读取，避免每个温度节点各启动两个 cat 进程。
        let hardwareCommand = "for f in /sys/class/thermal/thermal_zone*; do [ -d \"$f\" ] || continue; type=; temp=; read -r type < \"$f/type\"; read -r temp < \"$f/temp\"; printf '%s:%s\\n' \"$type\" \"$temp\"; done; read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat; printf 'cpu %s %s %s %s %s %s %s %s %s %s\\n' \"$user\" \"$nice\" \"$system\" \"$idle\" \"$iowait\" \"$irq\" \"$softirq\" \"$steal\" \"$guest\" \"$guest_nice\"; while IFS= read -r line; do case \"$line\" in MemTotal:*|MemAvailable:*|MemFree:*|Buffers:*|Cached:*) printf '%s\\n' \"$line\";; esac; done < /proc/meminfo"

        let hardwareTask = needsHardware ? Task {
            await ADBHardwareFetcher.executeShell(
                host: host,
                port: 5555,
                command: hardwareCommand,
                timeoutSec: 3.0
            )
        } : nil
        let qosTask = needsQos ? Task {
            await ADBHardwareFetcher.executeAT(
                host: host,
                port: 5555,
                command: "AT+CGEQOSRDP=1",
                timeoutSec: 3.0
            )
        } : nil

        if needsHardware { lastADBHardwareRefreshDate = now }
        if needsQos { lastADBQosRefreshDate = now }

        let rawHardware = await hardwareTask?.value
        let rawQos = await qosTask?.value
        if let rawHardware, !rawHardware.isEmpty {
            appendLog("降级", "5555 ADB 硬件指标读取成功")
            diagnosticChannelMode = diagnosticChannelMode == "未知" ? "5555 ADB" : "\(diagnosticChannelMode) + 5555 ADB"
            var metrics: [String: Any] = [:]
            parseLinuxShellOutput(rawHardware, into: &metrics)
            var adbStatus = F50Status()
            adbStatus.mergeHardwareMetrics(from: metrics)
            if primaryStatus.cpuUsage <= 0, adbStatus.cpuUsage > 0 {
                status.cpuUsage = adbStatus.cpuUsage
            }
            if primaryStatus.memUsage <= 0, adbStatus.memUsage > 0 {
                status.memUsage = adbStatus.memUsage
            }
            if primaryStatus.temperature <= 0, adbStatus.temperature > 0 {
                status.temperature = adbStatus.temperature
            }
        }
        if let rawQos,
           let qos = F50ResponseParser.parseQos(rawQos) {
            if primaryStatus.qci.isEmpty { status.qci = qos.qci }
            if primaryStatus.qosDl.isEmpty { status.qosDl = qos.downlink }
            if primaryStatus.qosUl.isEmpty { status.qosUl = qos.uplink }
        }
        if status.cpuUsage > 0 || status.memUsage > 0 || status.temperature > 0 || !status.qci.isEmpty {
            status.ufiAuthFailed = false
        }
    }

    /// UFI cellularUsage：按日期范围精确查询当日/本月用量。
    /// 结果写入独立字段 ufiDailyUsage/ufiMonthlyUsage，不覆盖套餐(Router)与其它字段。
    /// 注意：设备重置会清空历史记录（这是正常的），不影响按区间查询当前周期。
    private func fetchCellularUsageMetrics(ufiBaseURL: String, candidateTokens: [String], generation: UInt) {
        guard generation == requestGeneration else { return }
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now)
              ) else {
            finishExtension(generation: generation)
            return
        }
        let todayEnd = tomorrowStart.addingTimeInterval(-0.001)

        let group = DispatchGroup()
        var dailyUsage: UInt64?
        var monthlyUsage: UInt64?

        group.enter()
        fetchCellularUsage(
            ufiBaseURL: ufiBaseURL,
            start: todayStart,
            end: todayEnd,
            candidateTokens: candidateTokens,
            generation: generation
        ) { usage in
            dailyUsage = usage
            group.leave()
        }

        group.enter()
        fetchCellularUsage(
            ufiBaseURL: ufiBaseURL,
            start: monthStart,
            end: todayEnd,
            candidateTokens: candidateTokens,
            generation: generation
        ) { usage in
            monthlyUsage = usage
            group.leave()
        }

        group.notify(queue: .main) {
            guard generation == self.requestGeneration else { return }
            if let dailyUsage {
                self.status.ufiDailyUsage = dailyUsage
            }
            if let monthlyUsage {
                self.status.ufiMonthlyUsage = monthlyUsage
            }
            self.finishExtension(generation: generation)
        }
    }

    private func fetchCellularUsage(
        ufiBaseURL: String,
        start: Date,
        end: Date,
        candidateTokens: [String],
        generation: UInt,
        completion: @escaping (UInt64?) -> Void
    ) {
        guard generation == requestGeneration,
              let tokenHash = candidateTokens.first,
              var components = URLComponents(string: "\(ufiBaseURL)/api/cellularUsage") else {
            completion(nil)
            return
        }

        components.queryItems = [
            URLQueryItem(name: "startTime", value: String(Int64(start.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "endTime", value: String(Int64(end.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "method", value: "date-range")
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }

        let request = signedUFIRequest(url: url, token: tokenHash)

        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                if let httpRes = response as? HTTPURLResponse,
                   httpRes.statusCode == 200,
                   let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let usage = F50ResponseParser.parseCellularUsage(json) {
                    completion(usage)
                } else if candidateTokens.count > 1 {
                    self.fetchCellularUsage(
                        ufiBaseURL: ufiBaseURL,
                        start: start,
                        end: end,
                        candidateTokens: Array(candidateTokens.dropFirst()),
                        generation: generation,
                        completion: completion
                    )
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }

    /// 从 UFI 地址推导 Router 后台地址
    private func routerBaseURL(from ufiBaseURL: String) -> String {
        F50Configuration.resolveEndpoints(from: ufiBaseURL).routerBaseURL
    }

    /// 获取套餐账单周期累计（monthly_rx/tx_bytes）与套餐限额/清零日。
    /// 注意：设备 80 端口带 Referer 即可匿名读取这些字段，无需 cookie。
    private func fetchPackageUsageMetrics(routerBaseURL: String, generation: UInt) {
        guard generation == requestGeneration else { return }
        // 附带实时速率字段：UFI 主路径(兜底)不提供 realtime_rx/tx_thrpt，速度仅来自 Router 接口
        let cmdList = "monthly_rx_bytes,monthly_tx_bytes,data_volume_limit_size,data_volume_limit_unit,traffic_clear_date,realtime_rx_thrpt,realtime_tx_thrpt,temperature,cpu_temp,internal_temperature,ic_temp,qci"
        guard let url = URL(string: "\(routerBaseURL)/goform/goform_get_cmd_process?multi_data=1&isTest=false&cmd=\(cmdList)") else {
            finishExtension(generation: generation)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        request.setValue("\(routerBaseURL)/index.html", forHTTPHeaderField: "Referer")
        if let cookie = sessionCookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        packageTask = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                defer { self.packageTask = nil }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                       let data,
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       dict["Error"] == nil,
                       let rx = dict["monthly_rx_bytes"],
                       let tx = dict["monthly_tx_bytes"] else {
                    self.finishExtension(generation: generation)
                    return
                }
                self.status.packageRx = F50ResponseParser.parseUInt64(rx)
                self.status.packageTx = F50ResponseParser.parseUInt64(tx)
                if let dl = dict["realtime_rx_thrpt"] {
                    self.status.dlSpeed = F50ResponseParser.parseDouble(dl)
                }
                if let ul = dict["realtime_tx_thrpt"] {
                    self.status.ulSpeed = F50ResponseParser.parseDouble(ul)
                }
                self.status.recordSpeed(dl: self.status.dlSpeed, ul: self.status.ulSpeed)
                self.status.mergeHardwareMetrics(from: dict)
                let limit = F50ResponseParser.parseTrafficLimit(
                    size: dict["data_volume_limit_size"],
                    unit: dict["data_volume_limit_unit"]
                )
                if limit > 0 {
                    self.status.trafficLimit = limit
                }
                let detectedDay = F50ResponseParser.extractFirstValidResetDay(from: dict)
                if detectedDay > 0 {
                    self.routerDetectedTrafficResetDay = detectedDay
                    UserDefaults.standard.set(
                        detectedDay,
                        forKey: F50Configuration.detectedTrafficResetDayDefaultsKey
                    )
                    self.updateEffectiveTrafficResetDay()
                }
                self.finishExtension(generation: generation)
            }
        }
        packageTask?.resume()
    }

    private func fetchBandMetrics(hostOnly: String, generation: UInt) {
        guard generation == requestGeneration else { return }
        let cmdList = "network_type,wan_active_band,lte_band,lte_ca_pcell_band,nr5g_action_band,nr5g_action_nsa_band,ZCELLINFO_band,Z5g_CELLINFO_band,nr_ca_pcell_band,qci,temperature,cpu_temp,ic_temp"
        guard let url = URL(
            string: "\(hostOnly)/goform/goform_get_cmd_process?multi_data=1&isTest=false&cmd=\(cmdList)"
        ) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        request.setValue("\(hostOnly)/index.html", forHTTPHeaderField: "Referer")
        if let cookie = sessionCookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        bandTask = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                defer { self.bandTask = nil }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                self.status.mergeHardwareMetrics(from: payload)
                let bands = F50ResponseParser.parseCurrentBands(from: payload, networkType: self.status.networkType)
                if bands.isEmpty {
                    return
                }
                self.status.currentBands = bands
            }
        }
        bandTask?.resume()
    }

    private func candidateTokens() -> [String] {
        let source = "\(ufiToken)|\n\(password)"
        if let cached = cachedCandidateTokens, cachedTokenSource == source {
            return cached
        }

        var candidateTokens: [String] = []
        let t1 = ufiToken.trimmingCharacters(in: .whitespaces)
        if !t1.isEmpty {
            candidateTokens.append(sha256(t1))
            candidateTokens.append(sha256(t1.lowercased()))
            candidateTokens.append(sha256(t1.uppercased()))
            candidateTokens.append(t1)
        }

        let t2 = password.trimmingCharacters(in: .whitespaces)
        if !t2.isEmpty {
            candidateTokens.append(sha256(t2))
            candidateTokens.append(sha256(t2.lowercased()))
            candidateTokens.append(sha256(t2.uppercased()))
            candidateTokens.append(t2)
        }

        candidateTokens.append(sha256(F50Configuration.defaultCredential))
        candidateTokens.append(F50Configuration.defaultCredential)

        var uniqueTokens: [String] = []
        for t in candidateTokens {
            if !uniqueTokens.contains(t) { uniqueTokens.append(t) }
        }
        cachedCandidateTokens = uniqueTokens
        cachedTokenSource = source
        return uniqueTokens
    }

    private func fetchQosMetrics(ufiBaseURL: String, candidateTokens: [String], generation: UInt) {
        guard generation == requestGeneration else { return }
        guard let tokenHash = candidateTokens.first,
              let url = URL(string: "\(ufiBaseURL)/api/AT?command=AT%2BCGEQOSRDP%3D1&slot=0") else {
            failQos(generation: generation)
            return
        }

        let request = signedUFIRequest(url: url, token: tokenHash)

        qosTask = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let rawResult: String
                    if let resStr = json["result"] as? String {
                        rawResult = resStr
                    } else if let resDict = json["result"] as? [String: Any], let c = resDict["content"] as? String {
                        rawResult = c
                    } else if let dataStr = json["data"] as? String {
                        rawResult = dataStr
                    } else if let dataDict = json["data"] as? [String: Any], let c = dataDict["content"] as? String {
                        rawResult = c
                    } else {
                        rawResult = ""
                    }

                    let stringToParse = rawResult.isEmpty ? (String(data: data, encoding: .utf8) ?? "") : rawResult
                    if let qos = F50ResponseParser.parseQos(stringToParse) {
                        self.status.qci = qos.qci
                        self.status.qosDl = qos.downlink
                        self.status.qosUl = qos.uplink
                        self.finishExtension(generation: generation)
                        return
                    }
                }

                if candidateTokens.count > 1 {
                    self.fetchQosMetrics(
                        ufiBaseURL: ufiBaseURL,
                        candidateTokens: Array(candidateTokens.dropFirst()),
                        generation: generation
                    )
                } else {
                    self.failQos(generation: generation)
                }
            }
        }
        qosTask?.resume()
    }

    private func fetchLinuxShellMetrics(
        ufiBaseURL: String,
        candidateTokens: [String],
        candidatePaths: [String] = ["/api/user_shell", "/api/root_shell"],
        generation: UInt
    ) {
        guard generation == requestGeneration else { return }
        guard let tokenHash = candidateTokens.first,
              let path = candidatePaths.first,
              let url = URL(string: "\(ufiBaseURL)\(path)") else {
            status.ufiAuthFailed = true
            finishExtension(generation: generation)
            return
        }

        let cmd = "cat /proc/stat | grep \"cpu \"; cat /proc/meminfo | grep -E \"MemTotal|MemAvailable|MemFree|Buffers|Cached\"; for f in /sys/class/thermal/thermal_zone*; do echo \"$(cat $f/type 2>/dev/null):$(cat $f/temp 2>/dev/null)\"; done; cat /proc/net/dev 2>/dev/null | grep -E \"rmnet|wlan|eth|usb\"; dumpsys netstats 2>/dev/null | grep -i -E \"rmnet|wlan\" | head -n 30; cat /data/data/com.kano*/files/* 2>/dev/null; cat /sdcard/ufi* 2>/dev/null"
        let bodyObj: [String: Any] = ["command": cmd]
        let body = try? JSONSerialization.data(withJSONObject: bodyObj, options: [])
        let request = signedUFIRequest(url: url, token: tokenHash, method: "POST", body: body)

        shellTask = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.requestGeneration else { return }
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                   let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let rawResult: String
                    if let dictRes = json["result"] as? [String: Any], let c = dictRes["content"] as? String {
                        rawResult = c
                    } else if let strRes = json["result"] as? String {
                        rawResult = strRes
                    } else if let dataStr = json["data"] as? String {
                        rawResult = dataStr
                    } else if let dataDict = json["data"] as? [String: Any], let c = dataDict["content"] as? String {
                        rawResult = c
                    } else {
                        rawResult = ""
                    }

                    var metrics: [String: Any] = [:]
                    self.parseLinuxShellOutput(rawResult, into: &metrics)
                    if !metrics.isEmpty || self.prevTotalCpu > 0 {
                        var fallbackStatus = F50Status()
                        fallbackStatus.mergeHardwareMetrics(from: metrics)
                        if self.status.cpuUsage <= 0, fallbackStatus.cpuUsage > 0 {
                            self.status.cpuUsage = fallbackStatus.cpuUsage
                        }
                        if self.status.memUsage <= 0, fallbackStatus.memUsage > 0 {
                            self.status.memUsage = fallbackStatus.memUsage
                        }
                        if self.status.temperature <= 0, fallbackStatus.temperature > 0 {
                            self.status.temperature = fallbackStatus.temperature
                        }
                        self.status.ufiAuthFailed = false
                        self.finishExtension(generation: generation)
                        return
                    }
                }

                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 404, candidatePaths.count > 1 {
                    self.fetchLinuxShellMetrics(
                        ufiBaseURL: ufiBaseURL,
                        candidateTokens: self.candidateTokens(),
                        candidatePaths: Array(candidatePaths.dropFirst()),
                        generation: generation
                    )
                } else if candidateTokens.count > 1 {
                    self.fetchLinuxShellMetrics(
                        ufiBaseURL: ufiBaseURL,
                        candidateTokens: Array(candidateTokens.dropFirst()),
                        candidatePaths: candidatePaths,
                        generation: generation
                    )
                } else if candidatePaths.count > 1 {
                    self.fetchLinuxShellMetrics(
                        ufiBaseURL: ufiBaseURL,
                        candidateTokens: self.candidateTokens(),
                        candidatePaths: Array(candidatePaths.dropFirst()),
                        generation: generation
                    )
                } else {
                    self.status.ufiAuthFailed = true
                    self.finishExtension(generation: generation)
                }
            }
        }
        shellTask?.resume()
    }

    private func failQos(generation: UInt) {
        guard generation == requestGeneration else { return }
        finishExtension(generation: generation)
    }

    private func finishExtension(generation: UInt) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard generation == requestGeneration else { return }
        pendingExtensionRequests = max(0, pendingExtensionRequests - 1)
        if pendingExtensionRequests == 0 {
            isFetchingExtensions = false
            shellTask = nil
            qosTask = nil
            packageTask = nil
        }
    }

    private func parseLinuxShellOutput(_ output: String, into dict: inout [String: Any]) {
        let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")

        var maxSocCpuTemp: Double = 0.0
        var fallbackTemp: Double = 0.0
        var totalNetDevRx: UInt64 = 0
        var totalNetDevTx: UInt64 = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. CPU Stat Line
            if trimmed.hasPrefix("cpu ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.dropFirst().compactMap { Double($0) }
                if parts.count >= 4 {
                    let total = parts.reduce(0, +)
                    let idle = parts[3] + (parts.count > 4 ? parts[4] : 0)

                    if prevTotalCpu > 0 {
                        let totalDelta = total - prevTotalCpu
                        let idleDelta = idle - prevIdleCpu
                        if totalDelta > 0 {
                            let usage = max(0.0, min(100.0, (1.0 - idleDelta / totalDelta) * 100.0))
                            dict["cpu_utility"] = usage
                        }
                    }
                    prevTotalCpu = total
                    prevIdleCpu = idle
                }
            }

            // 2. Memory Lines
            if trimmed.hasPrefix("MemTotal:") {
                let clean = trimmed.replacingOccurrences(of: "MemTotal:", with: "").replacingOccurrences(of: "kB", with: "").trimmingCharacters(in: .whitespaces)
                if let totalKb = Double(clean) {
                    dict["_mem_total"] = totalKb
                }
            }
            if trimmed.hasPrefix("MemAvailable:") {
                let clean = trimmed.replacingOccurrences(of: "MemAvailable:", with: "").replacingOccurrences(of: "kB", with: "").trimmingCharacters(in: .whitespaces)
                if let availKb = Double(clean) {
                    dict["_mem_avail"] = availKb
                }
            }
            if trimmed.hasPrefix("MemFree:") {
                let clean = trimmed.replacingOccurrences(of: "MemFree:", with: "").replacingOccurrences(of: "kB", with: "").trimmingCharacters(in: .whitespaces)
                if let freeKb = Double(clean) {
                    dict["_mem_free"] = freeKb
                }
            }
            if trimmed.hasPrefix("Buffers:") {
                let clean = trimmed.replacingOccurrences(of: "Buffers:", with: "").replacingOccurrences(of: "kB", with: "").trimmingCharacters(in: .whitespaces)
                if let bufKb = Double(clean) {
                    dict["_mem_buffers"] = bufKb
                }
            }
            if trimmed.hasPrefix("Cached:") {
                let clean = trimmed.replacingOccurrences(of: "Cached:", with: "").replacingOccurrences(of: "kB", with: "").trimmingCharacters(in: .whitespaces)
                if let cacheKb = Double(clean) {
                    dict["_mem_cached"] = cacheKb
                }
            }

            // 3. Thermal Zone Lines: "type:temp" e.g. "soc-thmzone:61190" or "nr0-thmzone:61180"
            let parts = trimmed.components(separatedBy: ":")
            if parts.count == 2 {
                let type = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                if let rawVal = Double(parts[1].trimmingCharacters(in: .whitespaces)), rawVal > 0 {
                    let valC = rawVal > 1000 ? rawVal / 1000.0 : rawVal
                    if valC > 10 && valC < 125 {
                        if type.contains("soc") || type.contains("cpu") || type.contains("nr") || type.contains("apcpu") || type.contains("tsens") || type.contains("modem") || type.contains("chip") {
                            if valC > maxSocCpuTemp { maxSocCpuTemp = valC }
                        } else {
                            if fallbackTemp == 0 { fallbackTemp = valC }
                        }
                    }
                }
            }

            // 4. Network Dev throughput: "rmnet_data0: 123456 ... 789012 ..."
            if trimmed.contains(":") && (trimmed.hasPrefix("rmnet") || trimmed.hasPrefix("wlan") || trimmed.hasPrefix("eth") || trimmed.hasPrefix("usb")) {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count == 2 {
                    let cols = parts[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if cols.count >= 9, let rx = UInt64(cols[0]), let tx = UInt64(cols[8]) {
                        totalNetDevRx &+= rx
                        totalNetDevTx &+= tx
                    }
                }
            }
        }

        // Memory %
        if let totalKb = dict["_mem_total"] as? Double, totalKb > 0 {
            let availKb: Double
            if let a = dict["_mem_avail"] as? Double {
                availKb = a
            } else if let free = dict["_mem_free"] as? Double {
                let buffers = dict["_mem_buffers"] as? Double ?? 0
                let cached = dict["_mem_cached"] as? Double ?? 0
                availKb = free + buffers + cached
            } else {
                availKb = 0
            }
            if availKb > 0 {
                let memUsage = max(0.0, min(100.0, (1.0 - availKb / totalKb) * 100.0))
                dict["mem_utility"] = memUsage
            }
        }

        // Temperature selection matching UFI-TOOLS web page
        let finalTemp = maxSocCpuTemp > 0 ? maxSocCpuTemp : fallbackTemp
        if finalTemp > 0 {
            dict["cpu_temp"] = finalTemp
            dict["ic_temp"] = finalTemp
            dict["temperature"] = finalTemp
        }

        // Realtime throughput calculation from Linux netdev counters
        if totalNetDevRx > 0 || totalNetDevTx > 0 {
            let now = Date()
            if let prevTime = prevNetDevTimestamp, prevNetDevRx > 0 {
                let dt = now.timeIntervalSince(prevTime)
                if dt >= 0.5 && dt <= 10.0 {
                    let rxDelta = Double(totalNetDevRx >= prevNetDevRx ? totalNetDevRx - prevNetDevRx : 0)
                    let txDelta = Double(totalNetDevTx >= prevNetDevTx ? totalNetDevTx - prevNetDevTx : 0)
                    let calcDl = rxDelta / dt
                    let calcUl = txDelta / dt
                    if self.status.dlSpeed <= 0 && calcDl > 0 {
                        self.status.dlSpeed = calcDl
                        self.status.recordSpeed(dl: self.status.dlSpeed, ul: self.status.ulSpeed)
                    }
                    if self.status.ulSpeed <= 0 && calcUl > 0 {
                        self.status.ulSpeed = calcUl
                        self.status.recordSpeed(dl: self.status.dlSpeed, ul: self.status.ulSpeed)
                    }
                }
            }
            prevNetDevRx = totalNetDevRx
            prevNetDevTx = totalNetDevTx
            prevNetDevTimestamp = now
        }
    }

    private func performZTELogin(hostOnly: String, completion: @escaping (Bool) -> Void) {
        guard !password.isEmpty else {
            completion(false)
            return
        }

        let ldURLString = "\(hostOnly)/goform/goform_get_cmd_process?isTest=false&cmd=LD&_=\(Int64(Date().timeIntervalSince1970 * 1000))"
        guard let ldURL = URL(string: ldURLString) else {
            completion(false)
            return
        }

        var ldReq = URLRequest(url: ldURL)
        ldReq.setValue("\(hostOnly)/index.html", forHTTPHeaderField: "Referer")
        ldReq.timeoutInterval = 4.0

        session.dataTask(with: ldReq) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                guard let data = data,
                      let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let ld = dict["LD"] as? String, !ld.isEmpty else {
                    completion(false)
                    return
                }

                let pwdHash1 = self.sha256(self.password)
                let pwdHash2 = self.sha256(pwdHash1 + ld).uppercased()

                guard let loginURL = URL(string: "\(hostOnly)/goform/goform_set_cmd_process") else {
                    completion(false)
                    return
                }

                var loginReq = URLRequest(url: loginURL)
                loginReq.httpMethod = "POST"
                loginReq.setValue("\(hostOnly)/index.html", forHTTPHeaderField: "Referer")
                loginReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

                let bodyString = "goformId=LOGIN&isTest=false&user=admin&password=\(pwdHash2)"
                loginReq.httpBody = bodyString.data(using: .utf8)
                loginReq.timeoutInterval = 4.0

                self.session.dataTask(with: loginReq) { [weak self] data, response, error in
                    guard let self else { return }
                    Task { @MainActor in
                        if let httpRes = response as? HTTPURLResponse,
                           let setCookie = httpRes.value(forHTTPHeaderField: "Set-Cookie") {
                            let cookieVal = setCookie.components(separatedBy: ";").first ?? setCookie
                            self.sessionCookie = cookieVal
                            completion(true)
                        } else if let data = data,
                                  let resDict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                                  let result = resDict["result"] as? Int, (result == 0 || result == 3) {
                            completion(true)
                        } else {
                            completion(false)
                        }
                    }
                }.resume()
            }
        }.resume()
    }

    private func updateStatusFailed(_ msg: String, generation: UInt) {
        guard generation == requestGeneration else { return }
        status.isOnline = false
        status.errorMessage = msg
        appendLog("错误", msg)
        isFetching = false
    }

    private func parseStatusDict(
        _ dict: [String: Any],
        preserveQos: Bool,
        refreshTraffic: Bool
    ) {
        let previousStatus = status
        var newStatus = F50Status()
        newStatus.isOnline = true
        newStatus.errorMessage = nil
        newStatus.ufiAuthFailed = status.ufiAuthFailed
        newStatus.lastUpdated = Date()
        for key in ["wa_inner_version", "wa_version", "cr_version"] {
            if let value = dict[key] as? String, !value.isEmpty {
                diagnosticFirmwareVersion = value
                break
            }
        }

        // 保留由独立异步请求维护的字段（cellularUsage / packageTask），
        // 避免每 2s 的主刷新把它们重置为 0 导致面板回退到错误值
        newStatus.ufiDailyUsage = status.ufiDailyUsage
        newStatus.ufiMonthlyUsage = status.ufiMonthlyUsage
        newStatus.packageRx = status.packageRx
        newStatus.packageTx = status.packageTx

        if preserveQos {
            newStatus.qci = status.qci
            newStatus.qosDl = status.qosDl
            newStatus.qosUl = status.qosUl
        }
        newStatus.cpuUsage = status.cpuUsage
        newStatus.memUsage = status.memUsage
        newStatus.temperature = status.temperature
        newStatus.smsUnreadCount = status.smsUnreadCount
        newStatus.mergeHardwareMetrics(from: dict)

        // Signal bar (signalbar, rssi, network_signalbar)
        if let val = dict["signalbar"] ?? dict["rssi"] ?? dict["network_signalbar"] {
            let bar = parseInt(val)
            newStatus.signalBar = min(5, max(0, bar))
        }

        newStatus.dlHistory = status.dlHistory
        newStatus.ulHistory = status.ulHistory

        // Speeds
        if let val = dict["realtime_rx_thrpt"] {
            newStatus.dlSpeed = parseDouble(val)
        }
        if let val = dict["realtime_tx_thrpt"] {
            newStatus.ulSpeed = parseDouble(val)
        }
        newStatus.recordSpeed(dl: newStatus.dlSpeed, ul: newStatus.ulSpeed)

        // Connected devices
        if let val = dict["wifi_access_sta_num"] ?? dict["station_num"] {
            newStatus.connectedDevices = parseInt(val)
        }
        if let val = dict["sms_unread_num"] ?? dict["sms_sim_unread_num"] {
            let rawCount = parseInt(val)
            if !self.smsMessages.isEmpty {
                newStatus.smsUnreadCount = self.smsMessages.filter { $0.isUnread }.count
            } else if !self.locallyReadSMSIds.isEmpty {
                newStatus.smsUnreadCount = max(0, rawCount - self.locallyReadSMSIds.count)
            } else {
                newStatus.smsUnreadCount = rawCount
            }
        } else if !self.smsMessages.isEmpty {
            newStatus.smsUnreadCount = self.smsMessages.filter { $0.isUnread }.count
        }

        // Network type parsing (20 -> 5G SA, 19 -> 5G NSA, 10/11 -> 4G LTE)
        var parsedType = ""
        if let rawType = dict["network_type"] {
            let typeStr = String(describing: rawType).trimmingCharacters(in: .whitespaces)
            if typeStr == "20" || typeStr.contains("5G SA") || typeStr.contains("5G_SA") {
                parsedType = "5G SA"
            } else if typeStr == "19" || typeStr.contains("5G NSA") || typeStr.contains("5G_NSA") {
                parsedType = "5G NSA"
            } else if typeStr == "10" || typeStr == "11" || typeStr.lowercased().contains("4g") || typeStr.lowercased().contains("lte") {
                parsedType = "4G LTE"
            } else if typeStr == "5G" || typeStr == "5g" {
                parsedType = "5G"
            } else if !typeStr.isEmpty && typeStr != "0" {
                parsedType = typeStr
            }
        }

        // Fallback / refinement for network type
        // F50 的显式 network_type 只返回泛化的 "5G"（不区分 SA/NSA），
        // 用信号指标进一步区分：仅 NR 有值=SA，NR+LTE 都有=NSA
        if parsedType.isEmpty || parsedType == "0" || parsedType == "5G" {
            let hasNR = F50ResponseParser.firstValidSignalValue(in: dict, keys: ["nr_rsrp", "Z5g_rsrp", "5g_rsrp"]) != nil
            let hasLTE = F50ResponseParser.firstValidSignalValue(in: dict, keys: ["lte_rsrp"]) != nil
            if hasNR && !hasLTE {
                parsedType = "5G SA"
            } else if hasNR && hasLTE {
                parsedType = "5G NSA"
            } else if hasLTE {
                parsedType = "4G LTE"
            } else if parsedType.isEmpty || parsedType == "0" {
                parsedType = "5G"
            }
        }
        newStatus.networkType = parsedType
        let currentBands = F50ResponseParser.parseCurrentBands(from: dict, networkType: parsedType)
        newStatus.currentBands = currentBands.isEmpty ? status.currentBands : currentBands

        // 3 Signal Metrics: RSRP, RSRQ, SINR/SNR
        // firstValidSignalValue 会跳过 null/"0"/无效值继续尝试下一个候选键，
        // 避免设备把不适用的字段置 null 时真实值被短路掉（表现为三项全部 N/A）
        let rsrpKeys = ["nr_rsrp", "Z5g_rsrp", "5g_rsrp", "lte_rsrp", "Nr_signal_strength"]
        let rsrqKeys = ["nr_rsrq", "Z5g_rsrq", "5g_rsrq", "lte_rsrq"]
        let snrKeys = ["nr_sinr", "5g_sinr", "lte_sinr", "sinr", "Nr_snr", "nr_snr", "Z5g_snr", "5g_snr", "lte_snr"]

        if let reading = F50ResponseParser.firstValidSignalReading(in: dict, keys: rsrpKeys) {
            newStatus.rsrp = "\(Int(reading.value)) dBm"
            newStatus.rsrpSource = reading.sourceKey
        }
        if let reading = F50ResponseParser.firstValidSignalReading(in: dict, keys: rsrqKeys) {
            newStatus.rsrq = "\(Int(reading.value)) dB"
            newStatus.rsrqSource = reading.sourceKey
        }
        if let reading = F50ResponseParser.firstValidSignalReading(in: dict, keys: snrKeys) {
            newStatus.snr = "\(Int(reading.value)) dB"
            newStatus.snrSource = reading.sourceKey
            newStatus.snrMetricKind = reading.noiseKind ?? .unknown
        }

        let identity = F50ResponseParser.parseServingCellIdentity(from: dict, networkType: parsedType)
        newStatus.pci = identity.pci
        newStatus.cellId = identity.cellId
        newStatus.tac = identity.tac
        newStatus.cellIdentitySource = identity.sourceSummary

        // QCI if returned by network
        if let val = dict["qci"] ?? dict["QCI"] ?? dict["5g_qci"] ?? dict["nr_qci"] {
            let str = String(describing: val).trimmingCharacters(in: .whitespacesAndNewlines)
            if !str.isEmpty && str != "0" && str != "null" && str != "nil" {
                newStatus.qci = str
            }
        }

        // Carrier / Provider
        if let val = dict["network_provider"] as? String, !val.isEmpty {
            newStatus.carrier = val
        }

        // PPP Status
        if let val = dict["ppp_status"] as? String, !val.isEmpty {
            newStatus.pppStatus = F50ResponseParser.parsePPPStatus(val)
        }

        // Battery
        if let val = dict["battery_value"] ?? dict["battery_vol_percent"] {
            newStatus.batteryValue = parseInt(val)
        }
        if let val = dict["battery_charging"] {
            let str = String(describing: val).lowercased()
            newStatus.isCharging = str == "1" || str == "true" || str == "charging"
        }

        if refreshTraffic {
            if let val = F50ResponseParser.preferredMonthlyTrafficCounter(
                in: dict,
                monthlyKey: "monthly_rx_bytes",
                totalKey: "total_rx_bytes"
            ) {
                newStatus.monthlyRx = parseUInt64(val)
            }
            if let val = F50ResponseParser.preferredMonthlyTrafficCounter(
                in: dict,
                monthlyKey: "monthly_tx_bytes",
                totalKey: "total_tx_bytes"
            ) {
                newStatus.monthlyTx = parseUInt64(val)
            }
            if let val = dict["realtime_rx_bytes"] {
                newStatus.realtimeRx = parseUInt64(val)
            }
            if let val = dict["realtime_tx_bytes"] {
                newStatus.realtimeTx = parseUInt64(val)
            }
            if let val = dict["day_rx_bytes"] ?? dict["today_rx_bytes"] {
                newStatus.dailyRx = parseUInt64(val)
            }
            if let val = dict["day_tx_bytes"] ?? dict["today_tx_bytes"] {
                newStatus.dailyTx = parseUInt64(val)
            }

            newStatus.monthlyOffsetBytes = self.monthlyOffsetBytes
            newStatus.dailyOffsetBytes = self.dailyOffsetBytes
            newStatus.trackedDaily = updateDailyTrafficTracking(
                currentMonthlyTotal: newStatus.monthlyTotal,
                currentSessionTotal: newStatus.sessionTotal
            )
            newStatus.trafficLimit = F50ResponseParser.parseTrafficLimit(
                size: dict["data_volume_limit_size"],
                unit: dict["data_volume_limit_unit"]
            )
            let detectedDay = F50ResponseParser.extractFirstValidResetDay(from: dict)
            if detectedDay > 0 {
                self.routerDetectedTrafficResetDay = detectedDay
                UserDefaults.standard.set(detectedDay, forKey: "F50_DetectedTrafficResetDay")
            }
            updateEffectiveTrafficResetDay()
            newStatus.trafficResetDay = self.status.trafficResetDay
        } else {
            newStatus.monthlyRx = status.monthlyRx
            newStatus.monthlyTx = status.monthlyTx
            newStatus.realtimeRx = status.realtimeRx
            newStatus.realtimeTx = status.realtimeTx
            newStatus.dailyRx = status.dailyRx
            newStatus.dailyTx = status.dailyTx
            newStatus.trackedDaily = status.trackedDaily
            newStatus.trafficLimit = status.trafficLimit
            updateEffectiveTrafficResetDay()
            newStatus.trafficResetDay = self.status.trafficResetDay
            newStatus.monthlyOffsetBytes = status.monthlyOffsetBytes
            newStatus.dailyOffsetBytes = status.dailyOffsetBytes
        }

        if newStatus.requiresQosRefresh(comparedTo: previousStatus) {
            // 网络上下文变化后不能继续展示旧承载的 QCI；仅保留本轮 80 端口明确返回的字段。
            var primaryQos = F50Status()
            primaryQos.mergeHardwareMetrics(from: dict)
            newStatus.qci = primaryQos.qci
            newStatus.qosDl = primaryQos.qosDl
            newStatus.qosUl = primaryQos.qosUl
            lastADBQosRefreshDate = .distantPast
        }

        self.status = newStatus
    }

    public func applyTrafficCalibration(customMonthlyGB: Double?, customDailyGB: Double?) {
        let rawMonthly = status.monthlyRx + status.monthlyTx
        if let monthlyGB = customMonthlyGB, monthlyGB >= 0 {
            let targetBytes = Int64(monthlyGB * 1024.0 * 1024.0 * 1024.0)
            let offset = targetBytes - Int64(clamping: rawMonthly)
            self.monthlyOffsetBytes = offset
            UserDefaults.standard.set(offset, forKey: F50Configuration.monthlyOffsetDefaultsKey)
        }

        let nativeDaily = status.dailyRx + status.dailyTx
        let rawDaily = nativeDaily > 0 ? nativeDaily : max(status.trackedDaily, status.sessionTotal)
        if let dailyGB = customDailyGB, dailyGB >= 0 {
            let targetBytes = Int64(dailyGB * 1024.0 * 1024.0 * 1024.0)
            let offset = targetBytes - Int64(clamping: rawDaily)
            self.dailyOffsetBytes = offset
            UserDefaults.standard.set(offset, forKey: F50Configuration.dailyOffsetDefaultsKey)
        }

        status.monthlyOffsetBytes = self.monthlyOffsetBytes
        status.dailyOffsetBytes = self.dailyOffsetBytes
    }

    private func updateDailyTrafficTracking(currentMonthlyTotal: UInt64, currentSessionTotal: UInt64) -> UInt64 {
        let defaults = UserDefaults.standard
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())

        let lastDate = defaults.string(forKey: "F50_DailyTrafficDate") ?? ""
        var startOfDayMonthlyBytes = UInt64(defaults.string(forKey: "F50_DailyTrafficStartBytes") ?? "") ?? 0

        if lastDate != todayStr {
            defaults.set(todayStr, forKey: "F50_DailyTrafficDate")
            defaults.set(String(currentMonthlyTotal), forKey: "F50_DailyTrafficStartBytes")
            startOfDayMonthlyBytes = currentMonthlyTotal
        } else if startOfDayMonthlyBytes == 0 && currentMonthlyTotal > 0 {
            defaults.set(String(currentMonthlyTotal), forKey: "F50_DailyTrafficStartBytes")
            startOfDayMonthlyBytes = currentMonthlyTotal
        }

        var calculatedDaily: UInt64 = 0
        if currentMonthlyTotal >= startOfDayMonthlyBytes {
            calculatedDaily = currentMonthlyTotal - startOfDayMonthlyBytes
        } else {
            defaults.set(String(currentMonthlyTotal), forKey: "F50_DailyTrafficStartBytes")
            calculatedDaily = 0
        }

        return max(calculatedDaily, currentSessionTotal)
    }

    private func parseInt(_ val: Any) -> Int {
        F50ResponseParser.parseInt(val)
    }

    private func parseDouble(_ val: Any) -> Double {
        F50ResponseParser.parseDouble(val)
    }

    private func parseUInt64(_ val: Any) -> UInt64 {
        F50ResponseParser.parseUInt64(val)
    }

    private func sha256(_ str: String) -> String {
        let digest = SHA256.hash(data: Data(str.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// UFI-TOOLS 设备的签名算法（设备端协议固定）：
    /// HMAC-MD5 后对前/后半段分别做 SHA-256，拼接后再 SHA-256，输出小写 hex。
    private func calcKanoSign(key: String, data: String) -> String {
        F50ResponseParser.kanoSign(key: key, data: data)
    }

    // MARK: - Device control

    public func fetchDeviceControlSnapshot() async throws -> F50DeviceControlSnapshot {
        guard !isDemoMode else { throw F50DeviceControlError.demoMode }
        let commands = [
            "ppp_status", "net_select", "lte_band_lock", "nr_band_lock",
            "station_list", "lan_station_list", "queryDeviceAccessControlList", "hostNameList",
            "apn_Current_index", "apn_mode", "apn_m_profile_name", "profile_name", "profile_name_ui",
            "apn_wan_apn", "apn_ppp_username", "apn_ppp_passwd", "apn_ppp_auth_mode", "apn_pdp_type",
            "dns_mode", "prefer_dns_manual", "standby_dns_manual"
        ].joined(separator: ",")
        let payload = try await controlGet(commands: commands)

        let ppp = stringValue(payload["ppp_status"]).lowercased()
        let isMobileDataEnabled = !["ppp_disconnected", "disconnected", "disconnect", "0", "off"].contains(ppp)
        let mode = F50NetworkMode(rawValue: stringValue(payload["net_select"])) ?? .automatic
        let apn = F50APNSettings(
            index: intValue(payload["apn_Current_index"] ?? payload["index"]),
            profileName: firstString(payload, keys: ["apn_m_profile_name", "profile_name", "profile_name_ui"]),
            apn: firstString(payload, keys: ["apn_wan_apn", "wan_apn_ui"]),
            username: firstString(payload, keys: ["apn_ppp_username", "ppp_username_ui"]),
            password: firstString(payload, keys: ["apn_ppp_passwd", "ppp_passwd_ui"]),
            authentication: firstString(payload, keys: ["apn_ppp_auth_mode", "ppp_auth_mode_ui"], fallback: "none"),
            pdpType: firstString(payload, keys: ["apn_pdp_type", "pdp_type_ui"], fallback: "IPv4v6"),
            primaryDNS: firstString(payload, keys: ["prefer_dns_manual", "prefer_dns_manual_ui"]),
            secondaryDNS: firstString(payload, keys: ["standby_dns_manual", "standby_dns_manual_ui"]),
            isAutomatic: stringValue(payload["apn_mode"]).lowercased() != "manual"
        )

        let blackMACs = splitList(payload["BlackMacList"])
        let blackNames = splitList(payload["BlackNameList"])
        var clients = parseClients(payload["station_list"], isWired: false)
        clients.append(contentsOf: parseClients(payload["lan_station_list"], isWired: true))
        for (index, mac) in blackMACs.enumerated() where !mac.isEmpty {
            clients.removeAll { $0.macAddress.caseInsensitiveCompare(mac) == .orderedSame }
            clients.append(F50WiFiClient(
                name: blackNames.indices.contains(index) ? blackNames[index] : "",
                ipAddress: "",
                macAddress: mac,
                isWired: false,
                isBlocked: true
            ))
        }

        return F50DeviceControlSnapshot(
            isMobileDataEnabled: isMobileDataEnabled,
            networkMode: mode,
            apn: apn,
            clients: clients.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            accessControlMode: firstString(payload, keys: ["AclMode"], fallback: "2"),
            lockedLTEBands: parseBands(payload["lte_band_lock"]),
            lockedNRBands: parseBands(payload["nr_band_lock"])
        )
    }

    public func setMobileDataEnabled(_ enabled: Bool) async throws {
        try await controlSet(["goformId": enabled ? "CONNECT_NETWORK" : "DISCONNECT_NETWORK"])
    }

    public func setNetworkMode(_ mode: F50NetworkMode) async throws {
        try await controlSet([
            "goformId": "SET_BEARER_PREFERENCE",
            "BearerPreference": mode.rawValue
        ])
    }

    public func saveAPNSettings(_ settings: F50APNSettings) async throws {
        guard !settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.apn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw F50DeviceControlError.rejected("请填写配置名称与 APN")
        }
        let dnsMode = settings.primaryDNS.isEmpty && settings.secondaryDNS.isEmpty ? "auto" : "manual"
        var parameters: [String: String] = [
            "goformId": "APN_PROC_EX", "apn_mode": "manual", "apn_action": "save",
            "profile_name": settings.profileName, "index": String(max(0, settings.index)),
            "wan_dial": "*99#", "apn_wan_dial": "*99#", "apn_select": "manual",
            "apn_pdp_type": settings.pdpType, "pdp_type": settings.pdpType,
            "apn_pdp_select": "auto", "pdp_select": "auto", "apn_pdp_addr": "", "pdp_addr": "",
            "apn_wan_apn": settings.apn, "wan_apn": settings.apn,
            "apn_ppp_auth_mode": settings.authentication, "ppp_auth_mode": settings.authentication,
            "apn_ppp_username": settings.username, "ppp_username": settings.username,
            "apn_ppp_passwd": settings.password, "ppp_passwd": settings.password,
            "dns_mode": dnsMode, "prefer_dns_manual": settings.primaryDNS,
            "standby_dns_manual": settings.secondaryDNS
        ]
        if settings.pdpType != "IP" {
            parameters.merge([
                "apn_ipv6_wan_apn": settings.apn, "ipv6_wan_apn": settings.apn,
                "apn_ipv6_ppp_auth_mode": settings.authentication, "ipv6_ppp_auth_mode": settings.authentication,
                "apn_ipv6_ppp_username": settings.username, "ipv6_ppp_username": settings.username,
                "apn_ipv6_ppp_passwd": settings.password, "ipv6_ppp_passwd": settings.password,
                "ipv6_dns_mode": "auto", "ipv6_prefer_dns_manual": "", "ipv6_standby_dns_manual": ""
            ]) { _, new in new }
        }
        try await controlSet(parameters)
        try await controlSet([
            "goformId": "APN_PROC_EX", "apn_mode": "manual", "apn_action": "set_default",
            "set_default_flag": "1", "apn_pdp_type": "", "index": String(max(0, settings.index))
        ])
    }

    public func useAutomaticAPN() async throws {
        try await controlSet(["goformId": "APN_PROC_EX", "apn_mode": "auto"])
    }

    public func setWiFiClient(
        _ client: F50WiFiClient,
        blocked: Bool,
        currentClients: [F50WiFiClient]
    ) async throws {
        var blockedClients = currentClients.filter(\.isBlocked)
        blockedClients.removeAll { $0.macAddress.caseInsensitiveCompare(client.macAddress) == .orderedSame }
        if blocked { blockedClients.append(client) }
        try await controlSet([
            "goformId": "setDeviceAccessControlList", "AclMode": "2",
            "WhiteMacList": "", "WhiteNameList": "",
            "BlackMacList": blockedClients.map(\.macAddress).joined(separator: ";"),
            "BlackNameList": blockedClients.map(\.name).joined(separator: ";")
        ])
    }

    public func setBandLock(lte: Set<Int>, nr: Set<Int>) async throws {
        let supportedLTE: Set<Int> = [1, 3, 5, 8, 34, 38, 39, 40, 41]
        let supportedNR: Set<Int> = [1, 5, 8, 28, 41, 78]
        let effectiveLTE = lte.isEmpty && nr.isEmpty ? supportedLTE : lte
        let effectiveNR = lte.isEmpty && nr.isEmpty ? supportedNR : nr
        try await controlSet([
            "goformId": "LTE_BAND_LOCK",
            "lte_band_lock": effectiveLTE.sorted().map(String.init).joined(separator: ",")
        ])
        try await controlSet([
            "goformId": "NR_BAND_LOCK",
            "nr_band_lock": effectiveNR.sorted().map(String.init).joined(separator: ",")
        ])
    }

    public func lockCell(pci: Int, earfcn: Int, is5G: Bool) async throws {
        guard (0...1007).contains(pci), earfcn > 0 else {
            throw F50DeviceControlError.rejected("PCI 或频点无效")
        }
        try await controlSet([
            "goformId": "CELL_LOCK", "pci": String(pci), "earfcn": String(earfcn),
            "rat": is5G ? "16" : "12"
        ])
    }

    public func unlockAllCells() async throws {
        try await controlSet(["goformId": "UNLOCK_ALL_CELL"])
    }

    public func rebootDevice() async throws {
        try await controlSet(["goformId": "REBOOT_DEVICE"])
    }

    private enum DeviceControlBackend {
        case ufi(token: String, cookie: String?)
        case router(cookie: String?)
    }

    private func controlGet(commands: String) async throws -> [String: Any] {
        let expectedKeys = commands.split(separator: ",").map(String.init)

        if let cookie = try? await controlLogin(backend: .router(cookie: nil)),
           let payload = try? await controlGetPayload(commands: commands, backend: .router(cookie: cookie)),
           expectedKeys.contains(where: { payload[$0] != nil }) {
            return payload
        }

        for token in candidateTokens() {
            if let payload = try? await controlGetPayload(commands: commands, backend: .ufi(token: token, cookie: nil)),
               expectedKeys.contains(where: { payload[$0] != nil }) {
                return payload
            }
        }
        throw F50DeviceControlError.unavailable
    }

    private func controlSet(_ parameters: [String: String]) async throws {
        guard !isDemoMode else { throw F50DeviceControlError.demoMode }
        var lastMessage = "设备拒绝了控制请求"

        do {
            let cookie = try await controlLogin(backend: .router(cookie: nil))
            let result = try await controlPost(parameters, backend: .router(cookie: cookie))
            if controlSucceeded(result) { return }
            lastMessage = firstString(result, keys: ["error", "message", "msg"], fallback: lastMessage)
        } catch {
            lastMessage = error.localizedDescription
        }

        for token in candidateTokens() {
            do {
                let cookie = try await controlLogin(backend: .ufi(token: token, cookie: nil))
                let result = try await controlPost(parameters, backend: .ufi(token: token, cookie: cookie))
                if controlSucceeded(result) { return }
                lastMessage = firstString(result, keys: ["error", "message", "msg"], fallback: lastMessage)
            } catch {
                lastMessage = error.localizedDescription
            }
        }
        throw F50DeviceControlError.rejected(lastMessage)
    }

    private func controlLogin(backend: DeviceControlBackend) async throws -> String {
        let ld = try await controlGetSingle(command: "LD", backend: backend)
        guard !ld.isEmpty else { throw F50DeviceControlError.unavailable }
        let loginPassword = F50ResponseParser.calculateLoginPasswordHash(tokenOrPassword: password, ld: ld)
        let body = formBody([
            "goformId": "LOGIN", "isTest": "false", "user": "admin", "password": loginPassword
        ])
        let request = try controlRequest(
            path: "goform/goform_set_cmd_process", backend: backend, method: "POST", body: body
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw F50DeviceControlError.unavailable
        }
        let sessionFallback: String?
        if case .ufi = backend {
            sessionFallback = sessionCookie
        } else {
            sessionFallback = nil
        }
        let cookie = http.value(forHTTPHeaderField: "kano-cookie")
            ?? http.value(forHTTPHeaderField: "Set-Cookie")?.split(separator: ";").first.map(String.init)
            ?? sessionFallback
        if let cookie, !cookie.isEmpty { return cookie }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], controlSucceeded(json) {
            return ""
        }
        throw F50DeviceControlError.rejected("中兴后台口令验证失败")
    }

    private func controlPost(_ parameters: [String: String], backend: DeviceControlBackend) async throws -> [String: Any] {
        let version = try await controlGetPayload(commands: "Language,cr_version,wa_inner_version", backend: backend)
        let rd = try await controlGetSingle(command: "RD", backend: backend)
        let wa = stringValue(version["wa_inner_version"])
        let cr = stringValue(version["cr_version"])
        guard !wa.isEmpty, !cr.isEmpty, !rd.isEmpty else { throw F50DeviceControlError.invalidResponse }
        var form = parameters
        form["isTest"] = "false"
        form["AD"] = sha256(sha256(wa + cr) + rd)
        let request = try controlRequest(
            path: "goform/goform_set_cmd_process", backend: backend, method: "POST", body: formBody(form)
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw F50DeviceControlError.invalidResponse
        }
        return json
    }

    private func controlGetPayload(commands: String, backend: DeviceControlBackend) async throws -> [String: Any] {
        let query = [
            URLQueryItem(name: "isTest", value: "false"),
            URLQueryItem(name: "multi_data", value: "1"),
            URLQueryItem(name: "cmd", value: commands),
            URLQueryItem(name: "_", value: String(Int64(Date().timeIntervalSince1970 * 1000)))
        ]
        let request = try controlRequest(path: "goform/goform_get_cmd_process", backend: backend, query: query)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw F50DeviceControlError.invalidResponse
        }
        return (json["data"] as? [String: Any]) ?? (json["result"] as? [String: Any]) ?? json
    }

    private func controlGetSingle(command: String, backend: DeviceControlBackend) async throws -> String {
        let payload = try await controlGetPayload(commands: command, backend: backend)
        return stringValue(payload[command])
    }

    private func controlRequest(
        path: String,
        backend: DeviceControlBackend,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        let baseURL: String
        let requestPath: String
        let token: String?
        let cookie: String?
        switch backend {
        case .ufi(let value, let session):
            baseURL = ufiURLString
            requestPath = "api/\(path)"
            token = value
            cookie = session
        case .router(let session):
            baseURL = routerURLString
            requestPath = path
            token = nil
            cookie = session
        }
        guard var components = URLComponents(string: "\(baseURL)/\(requestPath)") else {
            throw F50DeviceControlError.unavailable
        }
        components.queryItems = query
        guard let url = components.url else { throw F50DeviceControlError.unavailable }
        var request = token.map {
            signedUFIRequest(url: url, token: $0, method: method, body: body,
                             contentType: "application/x-www-form-urlencoded; charset=UTF-8")
        } ?? URLRequest(url: url)
        if token == nil {
            request.httpMethod = method
            request.timeoutInterval = 4.0
            request.httpBody = body
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
            request.setValue(baseURL, forHTTPHeaderField: "Origin")
            request.setValue("\(baseURL)/index.html", forHTTPHeaderField: "Referer")
        }
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            if token != nil { request.setValue(cookie, forHTTPHeaderField: "kano-cookie") }
        }
        return request
    }

    private func formBody(_ parameters: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = parameters.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func controlSucceeded(_ json: [String: Any]) -> Bool {
        let value = stringValue(json["result"] ?? json["success"] ?? json["status"]).lowercased()
        return ["success", "true", "ok", "0", "3"].contains(value)
    }

    private func parseClients(_ value: Any?, isWired: Bool) -> [F50WiFiClient] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let mac = firstString(row, keys: ["mac_addr", "mac", "macAddress"])
            guard !mac.isEmpty else { return nil }
            return F50WiFiClient(
                name: firstString(row, keys: ["hostname", "name", "host_name"]),
                ipAddress: firstString(row, keys: ["ip_addr", "ip", "ipAddress"]),
                macAddress: mac,
                isWired: isWired,
                isBlocked: false
            )
        }
    }

    private func splitList(_ value: Any?) -> [String] {
        stringValue(value).split(separator: ";", omittingEmptySubsequences: false).map(String.init)
    }

    private func parseBands(_ value: Any?) -> Set<Int> {
        Set(stringValue(value).split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    private func firstString(
        _ payload: [String: Any],
        keys: [String],
        fallback: String = ""
    ) -> String {
        for key in keys {
            let value = stringValue(payload[key])
            if !value.isEmpty { return value }
        }
        return fallback
    }

    private func stringValue(_ value: Any?) -> String {
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        return Int(stringValue(value)) ?? 0
    }
}

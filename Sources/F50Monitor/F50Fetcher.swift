import Foundation
import Combine
import CryptoKit

@MainActor
public class F50Fetcher: ObservableObject {
    private enum ConnectionMode {
        case automatic
        case zteRouter
        case ufiAPI
    }

    @Published public var status: F50Status = F50Status()
    @Published public var baseURLString: String {
        didSet {
            if baseURLString != oldValue {
                UserDefaults.standard.set(baseURLString, forKey: F50Configuration.baseURLDefaultsKey)
                if !isApplyingConfiguration { configurationDidChange() }
            }
        }
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

    private var timer: Timer?
    private var isFetching: Bool = false
    private var sessionCookie: String? = nil
    private var requestGeneration: UInt = 0
    private var baseTask: URLSessionDataTask?
    private var bandTask: URLSessionDataTask?
    private var shellTask: URLSessionDataTask?
    private var qosTask: URLSessionDataTask?
    private var packageTask: URLSessionDataTask?
    private var smsTask: URLSessionDataTask?
    private var isFetchingExtensions = false
    private var pendingExtensionRequests = 0
    private var isApplyingConfiguration = false
    private var lastTrafficRefreshDate = Date.distantPast
    private var connectionMode: ConnectionMode = .automatic

    // token 候选缓存：凭据不变时避免每个轮询周期重复计算 SHA-256
    private var cachedCandidateTokens: [String]?
    private var cachedTokenSource = ""

    // CPU delta tracking
    private var prevTotalCpu: Double = 0
    private var prevIdleCpu: Double = 0
    private var routerDetectedTrafficResetDay: Int = 0

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
            self.displayMode = .full
        }

        updateEffectiveTrafficResetDay()
        startTimer()
        fetchData()
    }

    public func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchData()
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
        guard !isFetching else { return }
        isFetching = true
        let generation = requestGeneration

        let cleanBase = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let endpoints = connectionEndpoints(from: cleanBase)

        let shouldRefreshTraffic = Date().timeIntervalSince(lastTrafficRefreshDate)
            >= F50Configuration.trafficRefreshInterval
        if connectionMode == .ufiAPI {
            executeUFIFetch(
                cleanBase: cleanBase,
                hostOnly: endpoints.routerBaseURL,
                ufiBaseURL: endpoints.ufiBaseURL,
                generation: generation,
                refreshTraffic: shouldRefreshTraffic
            )
        } else {
            // .automatic / .zteRouter：Router 优先（速度/信号/套餐字段齐全），失败时 UFI 兜底
            executeFetch(
                cleanBase: cleanBase,
                hostOnly: endpoints.routerBaseURL,
                ufiBaseURL: endpoints.ufiBaseURL,
                generation: generation,
                refreshTraffic: shouldRefreshTraffic,
                allowsUFIFallback: true
            )
        }
    }

    public func fetchSMSMessages() {
        guard !isFetchingSMS else { return }

        let generation = requestGeneration
        let cleanBase = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let ufiBaseURL = connectionEndpoints(from: cleanBase).ufiBaseURL
        let tokens = candidateTokens()

        guard !tokens.isEmpty else {
            smsErrorMessage = "请先配置 UFI-TOOLS 登录口令"
            return
        }

        isFetchingSMS = true
        smsErrorMessage = nil
        fetchSMSMessages(
            ufiBaseURL: ufiBaseURL,
            candidateTokens: tokens,
            generation: generation
        )
    }

    private func fetchSMSMessages(
        ufiBaseURL: String,
        candidateTokens: [String],
        generation: UInt
    ) {
        guard generation == requestGeneration,
              let token = candidateTokens.first,
              var components = URLComponents(string: "\(ufiBaseURL)/api/goform/goform_get_cmd_process") else {
            finishSMSFetch(message: "短信接口地址无效", generation: generation)
            return
        }

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

        guard let url = components.url else {
            finishSMSFetch(message: "短信接口地址无效", generation: generation)
            return
        }

        smsTask = URLSession.shared.dataTask(with: signedUFIRequest(url: url, token: token)) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self, generation == self.requestGeneration else { return }

                if let http = response as? HTTPURLResponse,
                   http.statusCode == 200,
                   let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let messages = F50ResponseParser.parseSMSMessages(json) {
                    self.smsMessages = messages
                    self.smsErrorMessage = nil
                    self.isFetchingSMS = false
                    self.smsTask = nil
                } else if candidateTokens.count > 1 {
                    self.fetchSMSMessages(
                        ufiBaseURL: ufiBaseURL,
                        candidateTokens: Array(candidateTokens.dropFirst()),
                        generation: generation
                    )
                } else {
                    self.finishSMSFetch(
                        message: error?.localizedDescription ?? "无法读取短信，请检查 UFI-TOOLS 登录口令与短信权限",
                        generation: generation
                    )
                }
            }
        }
        smsTask?.resume()
    }

    private func finishSMSFetch(message: String, generation: UInt) {
        guard generation == requestGeneration else { return }
        smsErrorMessage = message
        isFetchingSMS = false
        smsTask = nil
    }

    private func connectionEndpoints(from cleanBase: String) -> (routerBaseURL: String, ufiBaseURL: String) {
        guard let url = URL(string: cleanBase), let host = url.host else {
            return ("http://192.168.0.1", "http://192.168.0.1:2333")
        }

        let scheme = url.scheme ?? "http"
        let routerBaseURL = "\(scheme)://\(host)"
        let port = url.port ?? 2333
        return (routerBaseURL, "\(scheme)://\(host):\(port)")
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
        executeUFIFetch(
            cleanBase: hostOnly,
            hostOnly: hostOnly,
            ufiBaseURL: ufiBaseURL,
            generation: generation,
            refreshTraffic: refreshTraffic
        )
    }

    private func executeUFIFetch(
        cleanBase: String,
        hostOnly: String,
        ufiBaseURL: String,
        generation: UInt,
        refreshTraffic: Bool,
        candidateTokens: [String]? = nil
    ) {
        guard generation == requestGeneration else { return }
        let tokens = candidateTokens ?? self.candidateTokens()
        guard let token = tokens.first,
              let url = URL(string: "\(ufiBaseURL)/api/baseDeviceInfo") else {
            updateStatusFailed("UFI API 地址无效", generation: generation)
            return
        }

        baseTask = URLSession.shared.dataTask(with: signedUFIRequest(url: url, token: token)) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self, generation == self.requestGeneration else { return }

                if let http = response as? HTTPURLResponse,
                   http.statusCode == 200,
                   let data,
                   let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.fetchUFISignalPayload(
                        ufiBaseURL: ufiBaseURL,
                        token: token,
                        generation: generation
                    ) { signalPayload in
                        var merged = payload
                        signalPayload?.forEach { merged[$0.key] = $0.value }
                        merged = F50ResponseParser.normalizeUFIPayload(merged)
                        guard generation == self.requestGeneration else { return }
                        self.connectionMode = .ufiAPI
                        self.parseStatusDict(merged, preserveQos: true, refreshTraffic: refreshTraffic)
                        if refreshTraffic {
                            self.lastTrafficRefreshDate = Date()
                        }
                        self.isFetching = false
                        self.fetchExtensionMetricsIfNeeded(
                            ufiBaseURL: ufiBaseURL,
                            generation: generation,
                            refreshTraffic: refreshTraffic
                        )
                    }
                } else if tokens.count > 1,
                          let http = response as? HTTPURLResponse,
                          http.statusCode == 401 {
                    // 401 = UFI 存在但 token 无效：尝试下一个候选
                    self.executeUFIFetch(
                        cleanBase: cleanBase,
                        hostOnly: hostOnly,
                        ufiBaseURL: ufiBaseURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        candidateTokens: Array(tokens.dropFirst())
                    )
                } else {
                    // UFI 服务不可达（连接失败/超时/非 401 错误）：立即兜底 Router，避免逐个试 token 拖慢恢复
                    self.connectionMode = .automatic
                    self.executeFetch(
                        cleanBase: cleanBase,
                        hostOnly: hostOnly,
                        ufiBaseURL: ufiBaseURL,
                        generation: generation,
                        refreshTraffic: refreshTraffic,
                        allowsUFIFallback: false
                    )
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
        let commands = "network_type,network_provider,signalbar,network_signalbar,nr_rsrp,nr_rsrq,Nr_snr,Z5g_rsrp,Z5g_rsrq,5g_snr,lte_rsrp,lte_rsrq,lte_snr,wifi_access_sta_num,sms_unread_num,sms_sim_unread_num,wan_active_band,lte_band,lte_ca_pcell_band,nr5g_action_band,nr5g_action_nsa_band,ZCELLINFO_band,Z5g_CELLINFO_band,nr_ca_pcell_band,data_volume_clear_day,monthly_clear_day,clear_day,data_volume_reset_day,billing_day,clear_date,reset_day,traffic_clear_date"
        // 注意：minikano goform 要求 cmd 参数放在第一位，否则最后一个字段名会被拼坏
        guard let url = URL(string: "\(ufiBaseURL)/api/goform/goform_get_cmd_process?cmd=\(commands)&is_all=true") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: signedUFIRequest(url: url, token: token)) { [weak self] data, response, _ in
            Task { @MainActor in
                guard let self, generation == self.requestGeneration else { return }
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(nil)
                    return
                }
                completion(payload)
            }
        }.resume()
    }

    /// 构建带 UFI-TOOLS 签名头部的请求（GET/POST 统一入口）
    private func signedUFIRequest(url: URL, token: String, method: String = "GET", body: Data? = nil) -> URLRequest {
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
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        let statusCommands = "usb_port_switch,battery_charging,sms_received_flag,sms_unread_num,sms_sim_unread_num,sim_msisdn,battery_value,battery_vol_percent,network_signalbar,network_rssi,cr_version,iccid,imei,imsi,ipv6_wan_ipaddr,lan_ipaddr,mac_address,msisdn,network_information,Lte_ca_status,rssi,Z5g_rsrp,lte_rsrp,wifi_access_sta_num,loginfo,realtime_rx_thrpt,realtime_tx_thrpt,network_type,network_provider,ppp_status,ic_temp,cpu_utility,mem_utility,nr_rsrp,nr_rsrq,Nr_snr,5g_rsrp,5g_rsrq,5g_snr,lte_rsrq,lte_snr,signalbar,qci,ambr,dl_ambr,ul_ambr"
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

        baseTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self, generation == self.requestGeneration else { return }

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

                if httpRes.statusCode == 401 && !isRetryAfterLogin {
                    self.performZTELogin(hostOnly: hostOnly) { [weak self] success in
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
                                "口令/密码错误(401)",
                                ufiBaseURL: ufiBaseURL,
                                generation: generation,
                                refreshTraffic: refreshTraffic,
                                allowsUFIFallback: allowsUFIFallback
                            )
                        }
                    }
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
                                self.performZTELogin(hostOnly: hostOnly) { [weak self] success in
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
                                            "设备登录失败: \(errorText)",
                                            ufiBaseURL: ufiBaseURL,
                                            generation: generation,
                                            refreshTraffic: refreshTraffic,
                                            allowsUFIFallback: allowsUFIFallback
                                        )
                                    }
                                }
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

                        self.connectionMode = .zteRouter
                        self.parseStatusDict(
                            dict,
                            preserveQos: true,
                            refreshTraffic: refreshTraffic
                        )
                        if refreshTraffic {
                            self.lastTrafficRefreshDate = Date()
                        }
                        self.isFetching = false
                        self.fetchBandMetrics(hostOnly: hostOnly, generation: generation)
                        self.fetchExtensionMetricsIfNeeded(
                            ufiBaseURL: ufiBaseURL,
                            generation: generation,
                            refreshTraffic: refreshTraffic
                        )
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
        isFetchingSMS = false
        smsMessages = []
        smsErrorMessage = nil
        sessionCookie = nil
        connectionMode = .automatic
        cachedCandidateTokens = nil
        cachedTokenSource = ""
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
    }

    private func fetchExtensionMetricsIfNeeded(
        ufiBaseURL: String,
        generation: UInt,
        refreshTraffic: Bool
    ) {
        guard !isFetchingExtensions else { return }
        let tokens = candidateTokens()
        guard !tokens.isEmpty else {
            clearQos(generation: generation)
            return
        }

        isFetchingExtensions = true
        pendingExtensionRequests = refreshTraffic ? 4 : 2
        fetchQosMetrics(ufiBaseURL: ufiBaseURL, candidateTokens: tokens, generation: generation)
        if refreshTraffic {
            // 当日/本月：UFI cellularUsage 按日期范围精确查询（与 F50 后台同口径）
            fetchCellularUsageMetrics(ufiBaseURL: ufiBaseURL, candidateTokens: tokens, generation: generation)
            // 套餐账单周期累计（Router 80 端口），与 UFI 的“本月已用”分开获取
            fetchPackageUsageMetrics(routerBaseURL: routerBaseURL(from: ufiBaseURL), generation: generation)
        }
        fetchLinuxShellMetrics(ufiBaseURL: ufiBaseURL, candidateTokens: tokens, generation: generation)
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

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            Task { @MainActor in
                guard let self, generation == self.requestGeneration else { return }
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

    /// 从 UFI 地址推导 Router 后台地址（去掉端口）
    private func routerBaseURL(from ufiBaseURL: String) -> String {
        guard let url = URL(string: ufiBaseURL), let host = url.host else {
            return "http://192.168.0.1"
        }
        return "\(url.scheme ?? "http")://\(host)"
    }

    /// 获取套餐账单周期累计（monthly_rx/tx_bytes）与套餐限额/清零日。
    /// 注意：设备 80 端口带 Referer 即可匿名读取这些字段，无需 cookie。
    private func fetchPackageUsageMetrics(routerBaseURL: String, generation: UInt) {
        guard generation == requestGeneration else { return }
        // 附带实时速率字段：UFI 主路径(兜底)不提供 realtime_rx/tx_thrpt，速度仅来自 Router 接口
        let cmdList = "monthly_rx_bytes,monthly_tx_bytes,data_volume_limit_size,data_volume_limit_unit,traffic_clear_date,realtime_rx_thrpt,realtime_tx_thrpt"
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

        packageTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            Task { @MainActor in
                guard let self, generation == self.requestGeneration else { return }
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
        let cmdList = "network_type,wan_active_band,lte_band,lte_ca_pcell_band,nr5g_action_band,nr5g_action_nsa_band,ZCELLINFO_band,Z5g_CELLINFO_band,nr_ca_pcell_band"
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

        bandTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            Task { @MainActor in
                guard let self, generation == self.requestGeneration else { return }
                defer { self.bandTask = nil }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
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

        qosTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            Task { @MainActor in
                guard let self = self, generation == self.requestGeneration else { return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? String,
                   let qos = F50ResponseParser.parseQos(result) {
                    self.status.qci = qos.qci
                    self.status.qosDl = qos.downlink
                    self.status.qosUl = qos.uplink
                    self.finishExtension(generation: generation)
                } else if candidateTokens.count > 1 {
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

    private func fetchLinuxShellMetrics(ufiBaseURL: String, candidateTokens: [String], generation: UInt) {
        guard generation == requestGeneration else { return }
        guard let tokenHash = candidateTokens.first,
              let url = URL(string: "\(ufiBaseURL)/api/user_shell") else {
            status.ufiAuthFailed = true
            finishExtension(generation: generation)
            return
        }

        let cmd = "cat /proc/stat | grep \"cpu \"; cat /proc/meminfo | grep -E \"MemTotal|MemAvailable\"; for f in /sys/class/thermal/thermal_zone*; do echo \"$(cat $f/type 2>/dev/null):$(cat $f/temp 2>/dev/null)\"; done; dumpsys netstats 2>/dev/null | grep -i -E \"rmnet|wlan\" | head -n 30; cat /data/data/com.kano*/files/* 2>/dev/null; cat /sdcard/ufi* 2>/dev/null"
        let bodyObj: [String: Any] = ["command": cmd]
        let body = try? JSONSerialization.data(withJSONObject: bodyObj, options: [])
        let request = signedUFIRequest(url: url, token: tokenHash, method: "POST", body: body)

        shellTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            Task { @MainActor in
                guard let self = self, generation == self.requestGeneration else { return }
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                   let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let rawResult: String
                    if let dictRes = json["result"] as? [String: Any], let c = dictRes["content"] as? String {
                        rawResult = c
                    } else if let strRes = json["result"] as? String {
                        rawResult = strRes
                    } else {
                        rawResult = ""
                    }

                    var metrics: [String: Any] = [:]
                    self.parseLinuxShellOutput(rawResult, into: &metrics)
                    self.status.mergeHardwareMetrics(from: metrics)
                    self.status.ufiAuthFailed = false
                    self.finishExtension(generation: generation)
                } else if candidateTokens.count > 1 {
                    self.fetchLinuxShellMetrics(
                        ufiBaseURL: ufiBaseURL,
                        candidateTokens: Array(candidateTokens.dropFirst()),
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

    private func clearQos(generation: UInt) {
        guard generation == requestGeneration else { return }
        status.qci = ""
        status.qosDl = ""
        status.qosUl = ""
    }

    private func failQos(generation: UInt) {
        guard generation == requestGeneration else { return }
        status.qci = ""
        status.qosDl = ""
        status.qosUl = ""
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

            // 3. Thermal Zone Lines: "type:temp" e.g. "soc-thmzone:61190" or "nr0-thmzone:61180"
            let parts = trimmed.components(separatedBy: ":")
            if parts.count == 2 {
                let type = parts[0].trimmingCharacters(in: .whitespaces)
                if let rawVal = Double(parts[1].trimmingCharacters(in: .whitespaces)), rawVal > 0 {
                    let valC = rawVal > 1000 ? rawVal / 1000.0 : rawVal
                    if valC > 10 && valC < 120 {
                        if type == "soc-thmzone" || type == "nr0-thmzone" || type == "apcpu0-thmzone" || type == "apcpu1-thmzone" || type == "cpu-thmzone" {
                            if valC > maxSocCpuTemp { maxSocCpuTemp = valC }
                        } else {
                            if fallbackTemp == 0 { fallbackTemp = valC }
                        }
                    }
                }
            }
        }

        // Memory %
        if let totalKb = dict["_mem_total"] as? Double, let availKb = dict["_mem_avail"] as? Double, totalKb > 0 {
            let memUsage = max(0.0, min(100.0, (1.0 - availKb / totalKb) * 100.0))
            dict["mem_utility"] = memUsage
        }

        // Temperature selection matching UFI-TOOLS web page
        let finalTemp = maxSocCpuTemp > 0 ? maxSocCpuTemp : fallbackTemp
        if finalTemp > 0 {
            dict["ic_temp"] = finalTemp
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

        URLSession.shared.dataTask(with: ldReq) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self, let data = data,
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

                URLSession.shared.dataTask(with: loginReq) { [weak self] data, response, error in
                    Task { @MainActor in
                        guard let self else { return }
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
        isFetching = false
    }

    private func parseStatusDict(
        _ dict: [String: Any],
        preserveQos: Bool,
        refreshTraffic: Bool
    ) {
        var newStatus = F50Status()
        newStatus.isOnline = true
        newStatus.errorMessage = nil
        newStatus.ufiAuthFailed = status.ufiAuthFailed
        newStatus.lastUpdated = Date()

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

        // Speeds
        if let val = dict["realtime_rx_thrpt"] {
            newStatus.dlSpeed = parseDouble(val)
        }
        if let val = dict["realtime_tx_thrpt"] {
            newStatus.ulSpeed = parseDouble(val)
        }

        // Connected devices
        if let val = dict["wifi_access_sta_num"] ?? dict["station_num"] {
            newStatus.connectedDevices = parseInt(val)
        }
        if let val = dict["sms_unread_num"] ?? dict["sms_sim_unread_num"] {
            newStatus.smsUnreadCount = parseInt(val)
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

        // Fallback for network type
        if parsedType.isEmpty || parsedType == "0" {
            if let rsrpVal = dict["nr_rsrp"] ?? dict["Z5g_rsrp"] ?? dict["5g_rsrp"], parseDouble(rsrpVal) != 0 {
                parsedType = "5G SA"
            } else if let lteVal = dict["lte_rsrp"], parseDouble(lteVal) != 0 {
                parsedType = "4G LTE"
            } else {
                parsedType = "5G"
            }
        }
        newStatus.networkType = parsedType
        let currentBands = F50ResponseParser.parseCurrentBands(from: dict, networkType: parsedType)
        newStatus.currentBands = currentBands.isEmpty ? status.currentBands : currentBands

        // 3 Signal Metrics: RSRP, RSRQ, SINR/SNR
        if let val = dict["nr_rsrp"] ?? dict["Z5g_rsrp"] ?? dict["5g_rsrp"] ?? dict["lte_rsrp"] {
            let num = parseDouble(val)
            if num != 0 { newStatus.rsrp = "\(Int(num)) dBm" }
        }
        if let val = dict["nr_rsrq"] ?? dict["Z5g_rsrq"] ?? dict["5g_rsrq"] ?? dict["lte_rsrq"] {
            let num = parseDouble(val)
            if num != 0 { newStatus.rsrq = "\(Int(num)) dB" }
        }
        if let val = dict["Nr_snr"] ?? dict["5g_snr"] ?? dict["lte_snr"] {
            let num = parseDouble(val)
            if num != 0 { newStatus.snr = "\(Int(num)) dB" }
        }

        // QCI if returned by network
        if let val = dict["qci"] ?? dict["QCI"] ?? dict["5g_qci"] ?? dict["nr_qci"], !String(describing: val).isEmpty {
            newStatus.qci = String(describing: val)
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
            if let val = dict["monthly_rx_bytes"] {
                newStatus.monthlyRx = parseUInt64(val)
            }
            if let val = dict["monthly_tx_bytes"] {
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
        let keyData = Data(key.utf8)
        let msgData = Data(data.utf8)
        let hmac = HMAC<Insecure.MD5>.authenticationCode(for: msgData, using: SymmetricKey(data: keyData))
        let hmacData = Data(hmac)
        let half = hmacData.count / 2
        let part1 = hmacData.subdata(in: 0..<half)
        let part2 = hmacData.subdata(in: half..<hmacData.count)

        let sha1 = SHA256.hash(data: part1)
        let sha2 = SHA256.hash(data: part2)

        var combined = Data()
        combined.append(contentsOf: sha1)
        combined.append(contentsOf: sha2)

        let finalHash = SHA256.hash(data: combined)
        return finalHash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

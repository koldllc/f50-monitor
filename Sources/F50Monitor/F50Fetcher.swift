import Foundation
import Combine
import CryptoKit

public class F50Fetcher: ObservableObject {
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
    
    private var timer: Timer?
    private var isFetching: Bool = false
    private var sessionCookie: String? = nil
    private var requestGeneration: UInt = 0
    private var baseTask: URLSessionDataTask?
    private var shellTask: URLSessionDataTask?
    private var qosTask: URLSessionDataTask?
    private var isFetchingExtensions = false
    private var pendingExtensionRequests = 0
    private var isApplyingConfiguration = false
    
    // CPU delta tracking
    private var prevTotalCpu: Double = 0
    private var prevIdleCpu: Double = 0
    
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
        
        if let modeData = UserDefaults.standard.data(forKey: F50Configuration.displayModeDefaultsKey),
           let mode = try? JSONDecoder().decode(MenuBarDisplayMode.self, from: modeData) {
            self.displayMode = mode
        } else {
            self.displayMode = .full
        }
        
        startTimer()
        fetchData()
    }
    
    public func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchData()
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
        displayMode: MenuBarDisplayMode
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
        let hostOnly: String
        if let url = URL(string: cleanBase), let host = url.host {
            hostOnly = "\(url.scheme ?? "http")://\(host)"
        } else {
            hostOnly = "http://192.168.0.1"
        }
        
        executeFetch(cleanBase: cleanBase, hostOnly: hostOnly, generation: generation)
    }
    
    private func executeFetch(cleanBase: String, hostOnly: String, generation: UInt, isRetryAfterLogin: Bool = false) {
        let cmdList = "usb_port_switch,battery_charging,sms_received_flag,sms_unread_num,sms_sim_unread_num,sim_msisdn,battery_value,battery_vol_percent,network_signalbar,network_rssi,cr_version,iccid,imei,imsi,ipv6_wan_ipaddr,lan_ipaddr,mac_address,msisdn,network_information,Lte_ca_status,rssi,Z5g_rsrp,lte_rsrp,wifi_access_sta_num,loginfo,realtime_rx_thrpt,realtime_tx_thrpt,realtime_rx_bytes,realtime_tx_bytes,realtime_time,monthly_tx_bytes,monthly_rx_bytes,monthly_time,data_volume_limit_size,data_volume_limit_unit,network_type,network_provider,ppp_status,ic_temp,cpu_utility,mem_utility,nr_rsrp,nr_rsrq,Nr_snr,5g_rsrp,5g_rsrq,5g_snr,lte_rsrq,lte_snr,signalbar,qci,ambr,dl_ambr,ul_ambr"
        
        let targetURLString = "\(hostOnly)/goform/goform_get_cmd_process?multi_data=1&isTest=false&cmd=\(cmdList)"
        
        guard let url = URL(string: targetURLString) else {
            updateStatusFailed("无效的 URL", generation: generation)
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
            guard let self = self, generation == self.requestGeneration else { return }
            
            if let error = error {
                self.updateStatusFailed(error.localizedDescription, generation: generation)
                return
            }
            
            guard let httpRes = response as? HTTPURLResponse else {
                self.updateStatusFailed("网络响应错误", generation: generation)
                return
            }
            
            if httpRes.statusCode == 401 && !isRetryAfterLogin {
                self.performZTELogin(hostOnly: hostOnly) { [weak self] success in
                    guard let self, generation == self.requestGeneration else { return }
                    if success {
                        self.executeFetch(cleanBase: cleanBase, hostOnly: hostOnly, generation: generation, isRetryAfterLogin: true)
                    } else {
                        self.updateStatusFailed("口令/密码错误(401)", generation: generation)
                    }
                }
                return
            }
            
            guard httpRes.statusCode == 200, let data = data else {
                self.updateStatusFailed("HTTP 错误: \(httpRes.statusCode)", generation: generation)
                return
            }
            
            do {
                if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    DispatchQueue.main.async {
                        guard generation == self.requestGeneration else { return }
                        self.parseStatusDict(dict, preserveQos: true)
                        self.isFetching = false
                        self.fetchExtensionMetricsIfNeeded(hostOnly: hostOnly, generation: generation)
                    }
                } else {
                    self.updateStatusFailed("解析 JSON 失败", generation: generation)
                }
            } catch {
                self.updateStatusFailed(error.localizedDescription, generation: generation)
            }
        }
        baseTask?.resume()
    }

    private func configurationDidChange() {
        requestGeneration &+= 1
        baseTask?.cancel()
        shellTask?.cancel()
        qosTask?.cancel()
        baseTask = nil
        shellTask = nil
        qosTask = nil
        isFetching = false
        isFetchingExtensions = false
        sessionCookie = nil
        status.qci = ""
        status.qosDl = ""
        status.qosUl = ""
        status.clearHardwareMetrics()
        prevTotalCpu = 0
        prevIdleCpu = 0
    }
    
    private func fetchExtensionMetricsIfNeeded(hostOnly: String, generation: UInt) {
        guard !isFetchingExtensions else { return }
        let tokens = candidateTokens()
        guard !tokens.isEmpty else {
            clearQos(generation: generation)
            return
        }

        isFetchingExtensions = true
        pendingExtensionRequests = 2
        fetchQosMetrics(hostOnly: hostOnly, candidateTokens: tokens, generation: generation)
        fetchLinuxShellMetrics(hostOnly: hostOnly, candidateTokens: tokens, generation: generation)
    }

    private func candidateTokens() -> [String] {
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
        return uniqueTokens
    }

    private func fetchQosMetrics(hostOnly: String, candidateTokens: [String], generation: UInt) {
        guard generation == requestGeneration else { return }
        guard let tokenHash = candidateTokens.first,
              let url = URL(string: "\(hostOnly):2333/api/AT?command=AT%2BCGEQOSRDP%3D1&slot=0") else {
            failQos(generation: generation)
            return
        }

        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let key = "minikano_kOyXz0Ciz4V7wR0IeKmJFYFQ20jd"
        let sign = calcKanoSign(key: key, data: "minikanoGET\(url.path)\(timestamp)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        request.setValue(timestamp, forHTTPHeaderField: "kano-t")
        request.setValue(sign, forHTTPHeaderField: "kano-sign")
        request.setValue(tokenHash, forHTTPHeaderField: "authorization")
        
        qosTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self, generation == self.requestGeneration else { return }
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String,
               let qos = F50ResponseParser.parseQos(result) {
                DispatchQueue.main.async {
                    guard generation == self.requestGeneration else { return }
                    self.status.qci = qos.qci
                    self.status.qosDl = qos.downlink
                    self.status.qosUl = qos.uplink
                    self.finishExtension(generation: generation)
                }
            } else if candidateTokens.count > 1 {
                self.fetchQosMetrics(
                    hostOnly: hostOnly,
                    candidateTokens: Array(candidateTokens.dropFirst()),
                    generation: generation
                )
            } else {
                self.failQos(generation: generation)
            }
        }
        qosTask?.resume()
    }

    private func fetchLinuxShellMetrics(hostOnly: String, candidateTokens: [String], generation: UInt) {
        guard generation == requestGeneration else { return }
        guard let tokenHash = candidateTokens.first,
              let url = URL(string: "\(hostOnly):2333/api/user_shell") else {
            DispatchQueue.main.async {
                guard generation == self.requestGeneration else { return }
                self.status.ufiAuthFailed = true
                self.finishExtension(generation: generation)
            }
            return
        }

        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let key = "minikano_kOyXz0Ciz4V7wR0IeKmJFYFQ20jd"
        let sign = calcKanoSign(key: key, data: "minikanoPOST\(url.path)\(timestamp)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(timestamp, forHTTPHeaderField: "kano-t")
        request.setValue(sign, forHTTPHeaderField: "kano-sign")
        request.setValue(tokenHash, forHTTPHeaderField: "authorization")
        
        let cmd = "cat /proc/stat | grep \"cpu \"; cat /proc/meminfo | grep -E \"MemTotal|MemAvailable\"; for f in /sys/class/thermal/thermal_zone*; do echo \"$(cat $f/type 2>/dev/null):$(cat $f/temp 2>/dev/null)\"; done"
        let bodyObj: [String: Any] = ["command": cmd]
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyObj, options: [])
        
        shellTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
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
                DispatchQueue.main.async {
                    guard generation == self.requestGeneration else { return }
                    self.status.mergeHardwareMetrics(from: metrics)
                    self.status.ufiAuthFailed = false
                    self.finishExtension(generation: generation)
                }
            } else if candidateTokens.count > 1 {
                self.fetchLinuxShellMetrics(
                    hostOnly: hostOnly,
                    candidateTokens: Array(candidateTokens.dropFirst()),
                    generation: generation
                )
            } else {
                DispatchQueue.main.async {
                    guard generation == self.requestGeneration else { return }
                    self.status.ufiAuthFailed = true
                    self.finishExtension(generation: generation)
                }
            }
        }
        shellTask?.resume()
    }

    private func clearQos(generation: UInt) {
        DispatchQueue.main.async {
            guard generation == self.requestGeneration else { return }
            self.status.qci = ""
            self.status.qosDl = ""
            self.status.qosUl = ""
        }
    }

    private func failQos(generation: UInt) {
        DispatchQueue.main.async {
            guard generation == self.requestGeneration else { return }
            self.status.qci = ""
            self.status.qosDl = ""
            self.status.qosUl = ""
            self.finishExtension(generation: generation)
        }
    }

    private func finishExtension(generation: UInt) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard generation == requestGeneration else { return }
        pendingExtensionRequests = max(0, pendingExtensionRequests - 1)
        if pendingExtensionRequests == 0 {
            isFetchingExtensions = false
            shellTask = nil
            qosTask = nil
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
            
            URLSession.shared.dataTask(with: loginReq) { data, response, error in
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
            }.resume()
        }.resume()
    }
    
    private func updateStatusFailed(_ msg: String, generation: UInt) {
        DispatchQueue.main.async {
            guard generation == self.requestGeneration else { return }
            self.status.isOnline = false
            self.status.errorMessage = msg
            self.isFetching = false
        }
    }
    
    private func parseStatusDict(_ dict: [String: Any], preserveQos: Bool) {
        var newStatus = F50Status()
        newStatus.isOnline = true
        newStatus.errorMessage = nil
        newStatus.ufiAuthFailed = status.ufiAuthFailed
        newStatus.lastUpdated = Date()
        
        if preserveQos {
            newStatus.qci = status.qci
            newStatus.qosDl = status.qosDl
            newStatus.qosUl = status.qosUl
        }
        newStatus.cpuUsage = status.cpuUsage
        newStatus.memUsage = status.memUsage
        newStatus.temperature = status.temperature
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
        
        // Monthly bytes
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
        newStatus.trafficLimit = F50ResponseParser.parseTrafficLimit(
            size: dict["data_volume_limit_size"],
            unit: dict["data_volume_limit_unit"]
        )
        
        self.status = newStatus
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

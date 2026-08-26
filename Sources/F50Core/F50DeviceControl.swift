import Foundation
import SwiftUI

public enum F50NetworkMode: String, CaseIterable, Identifiable, Sendable {
    case automatic = "WL_AND_5G"
    case fiveGNSA = "LTE_AND_5G"
    case fiveGSA = "Only_5G"
    case fourGAndThreeG = "WCDMA_AND_LTE"
    case fourGOnly = "Only_LTE"
    case threeGOnly = "Only_WCDMA"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "自动（5G / 4G / 3G）"
        case .fiveGNSA: return "5G NSA"
        case .fiveGSA: return "5G SA"
        case .fourGAndThreeG: return "4G / 3G"
        case .fourGOnly: return "仅 4G"
        case .threeGOnly: return "仅 3G"
        }
    }
}

public enum F50USBNetworkProtocol: String, CaseIterable, Identifiable, Sendable {
    case automatic = "0"
    case rndis = "1"
    case cdcECM = "2"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "自动"
        case .rndis: return "RNDIS"
        case .cdcECM: return "CDC-ECM"
        }
    }
}

public enum F50WiFiRadioMode: String, CaseIterable, Identifiable, Sendable {
    case only24GHz = "1"
    case only5GHz = "2"
    case off = "0"

    public var id: String { rawValue }

    var firmwareChipEnum: String? {
        switch self {
        case .only24GHz: return "chip1"
        case .only5GHz: return "chip2"
        case .off: return nil
        }
    }

    var firmwareChipIndex: String? {
        switch self {
        case .only24GHz: return "0"
        case .only5GHz: return "1"
        case .off: return nil
        }
    }

    static func resolve(
        moduleSwitch: String,
        chip24Enabled: Bool?,
        chip5Enabled: Bool?
    ) -> F50WiFiRadioMode {
        if ["0", "off", "disabled", "false"].contains(moduleSwitch.lowercased()) {
            return .off
        }
        if chip5Enabled == true, chip24Enabled != true { return .only5GHz }
        if chip24Enabled == true { return .only24GHz }
        if chip5Enabled == true { return .only5GHz }
        return .only24GHz
    }

    public var title: String {
        switch self {
        case .only24GHz: return "仅 2.4 GHz"
        case .only5GHz: return "仅 5 GHz"
        case .off: return "关闭"
        }
    }
}

public enum F50WiFiSecurityMode: String, CaseIterable, Identifiable, Sendable {
    case open = "OPEN"
    case wpa2AES = "WPA2PSK"
    case wpaWpa2 = "WPAPSKWPA2PSK"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .open: return "开放网络"
        case .wpa2AES: return "WPA2 (AES)-PSK"
        case .wpaWpa2: return "WPA / WPA2-PSK"
        }
    }
}

public struct F50WiFiSettings: Equatable, Sendable {
    public var radioMode: F50WiFiRadioMode
    public var ssid: String
    public var broadcastsSSID: Bool
    public var securityMode: F50WiFiSecurityMode
    public var password: String
    public var maximumClients: Int
    public var usesEncodedPassword: Bool
    public var noForwarding: String
    public var qrCodeDisplaySwitch: String

    public init(
        radioMode: F50WiFiRadioMode = .only5GHz,
        ssid: String = "",
        broadcastsSSID: Bool = true,
        securityMode: F50WiFiSecurityMode = .wpa2AES,
        password: String = "",
        maximumClients: Int = 10,
        usesEncodedPassword: Bool = false,
        noForwarding: String = "0",
        qrCodeDisplaySwitch: String = "1"
    ) {
        self.radioMode = radioMode
        self.ssid = ssid
        self.broadcastsSSID = broadcastsSSID
        self.securityMode = securityMode
        self.password = password
        self.maximumClients = maximumClients
        self.usesEncodedPassword = usesEncodedPassword
        self.noForwarding = noForwarding
        self.qrCodeDisplaySwitch = qrCodeDisplaySwitch
    }
}

public struct F50WiFiClient: Identifiable, Hashable, Sendable {
    public let name: String
    public let ipAddress: String
    public let macAddress: String
    public let isWired: Bool
    public let isBlocked: Bool

    public var id: String { macAddress.lowercased() }
}

public struct F50NeighborCell: Identifiable, Hashable, Sendable {
    public let band: String
    public let earfcn: Int
    public let pci: Int
    public let rsrp: String
    public let rsrq: String
    public let sinr: String
    public let is5G: Bool

    public var id: String { "\(is5G ? "5G" : "4G")-\(band)-\(earfcn)-\(pci)" }
    public var radioTitle: String { is5G ? "5G" : "4G" }
    public var bandTitle: String { "\(is5G ? "n" : "B")\(band)" }
}

public struct F50APNSettings: Equatable, Sendable {
    public var index: Int
    public var profileName: String
    public var apn: String
    public var username: String
    public var password: String
    public var authentication: String
    public var pdpType: String
    public var isAutomatic: Bool

    public init(
        index: Int = 0,
        profileName: String = "",
        apn: String = "",
        username: String = "",
        password: String = "",
        authentication: String = "none",
        pdpType: String = "IPv4v6",
        isAutomatic: Bool = true
    ) {
        self.index = index
        self.profileName = profileName
        self.apn = apn
        self.username = username
        self.password = password
        self.authentication = authentication
        self.pdpType = pdpType
        self.isAutomatic = isAutomatic
    }
}

public enum F50TrafficUnit: String, CaseIterable, Identifiable, Sendable {
    case megabytes = "0"
    case gigabytes = "1"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .megabytes: return "MB"
        case .gigabytes: return "GB"
        }
    }
}

public struct F50TrafficManagementSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var clearsAutomatically: Bool
    public var clearDay: Int
    public var used: Double
    public var usedUnit: F50TrafficUnit
    public var limit: Int
    public var unit: F50TrafficUnit
    public var reminderPercentage: Int

    public init(
        isEnabled: Bool = false,
        clearsAutomatically: Bool = true,
        clearDay: Int = 1,
        used: Double = 0,
        usedUnit: F50TrafficUnit = .gigabytes,
        limit: Int = 0,
        unit: F50TrafficUnit = .gigabytes,
        reminderPercentage: Int = 90
    ) {
        self.isEnabled = isEnabled
        self.clearsAutomatically = clearsAutomatically
        self.clearDay = clearDay
        self.used = used
        self.usedUnit = usedUnit
        self.limit = limit
        self.unit = unit
        self.reminderPercentage = reminderPercentage
    }
}

public struct F50DeviceControlSnapshot: Sendable {
    public var isMobileDataEnabled: Bool
    public var networkMode: F50NetworkMode
    public var usbNetworkProtocol: F50USBNetworkProtocol
    public var wifi: F50WiFiSettings
    public var apn: F50APNSettings
    public var trafficManagement: F50TrafficManagementSettings
    public var clients: [F50WiFiClient]
    public var accessControlMode: String
    public var lockedLTEBands: Set<Int>
    public var lockedNRBands: Set<Int>
    public var currentCell: F50NeighborCell?
    public var neighborCells: [F50NeighborCell]

    public init(
        isMobileDataEnabled: Bool = false,
        networkMode: F50NetworkMode = .automatic,
        usbNetworkProtocol: F50USBNetworkProtocol = .automatic,
        wifi: F50WiFiSettings = F50WiFiSettings(),
        apn: F50APNSettings = F50APNSettings(),
        trafficManagement: F50TrafficManagementSettings = F50TrafficManagementSettings(),
        clients: [F50WiFiClient] = [],
        accessControlMode: String = "2",
        lockedLTEBands: Set<Int> = [],
        lockedNRBands: Set<Int> = [],
        currentCell: F50NeighborCell? = nil,
        neighborCells: [F50NeighborCell] = []
    ) {
        self.isMobileDataEnabled = isMobileDataEnabled
        self.networkMode = networkMode
        self.usbNetworkProtocol = usbNetworkProtocol
        self.wifi = wifi
        self.apn = apn
        self.trafficManagement = trafficManagement
        self.clients = clients
        self.accessControlMode = accessControlMode
        self.lockedLTEBands = lockedLTEBands
        self.lockedNRBands = lockedNRBands
        self.currentCell = currentCell
        self.neighborCells = neighborCells
    }
}

public enum F50DeviceControlError: LocalizedError {
    case demoMode
    case unavailable
    case invalidResponse
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .demoMode:
            return "演示模式不会修改真实设备"
        case .unavailable:
            return "设备控制不可用，请检查中兴后台口令，以及 2333 或 Router 80 服务"
        case .invalidResponse:
            return "设备返回了无法识别的数据"
        case .rejected(let message):
            return message
        }
    }
}

@MainActor
public final class F50DeviceControlModel: ObservableObject {
    @Published public private(set) var snapshot = F50DeviceControlSnapshot()
    @Published public private(set) var isLoading = false
    @Published public private(set) var isApplying = false
    @Published public var errorMessage: String?
    @Published public var successMessage: String?

    private let fetcher: F50Fetcher

    public init(fetcher: F50Fetcher) {
        self.fetcher = fetcher
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            snapshot = try await fetcher.fetchDeviceControlSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setMobileData(_ enabled: Bool) async {
        await apply(success: enabled ? "移动数据已开启" : "移动数据已关闭") {
            try await fetcher.setMobileDataEnabled(enabled)
        }
    }

    public func setNetworkMode(_ mode: F50NetworkMode) async {
        await apply(success: "网络模式已切换为 \(mode.title)") {
            try await fetcher.setNetworkMode(mode)
        }
    }

    public func setUSBNetworkProtocol(_ usbProtocol: F50USBNetworkProtocol) async {
        await apply(success: "USB 上网协议已切换为 \(usbProtocol.title)") {
            try await fetcher.setUSBNetworkProtocol(usbProtocol)
        }
    }

    public func saveWiFi(_ settings: F50WiFiSettings) async {
        await apply(success: "Wi-Fi 设置已保存", refreshAfterward: false) {
            try await fetcher.saveWiFiSettings(settings)
        }
        if errorMessage == nil {
            snapshot.wifi = settings
        }
    }

    public func saveAPN(_ settings: F50APNSettings) async {
        await apply(success: "APN 已保存") {
            try await fetcher.saveAPNSettings(settings)
        }
    }

    public func useAutomaticAPN() async {
        await apply(success: "已恢复自动 APN") {
            try await fetcher.useAutomaticAPN()
        }
    }

    public func saveTrafficManagement(_ settings: F50TrafficManagementSettings) async {
        await apply(success: "流量管理设置已保存") {
            try await fetcher.saveTrafficManagement(settings)
        }
    }

    public func setClientBlocked(_ client: F50WiFiClient, blocked: Bool) async {
        await apply(success: blocked ? "设备已加入黑名单" : "设备已解除黑名单") {
            try await fetcher.setWiFiClient(client, blocked: blocked, currentClients: snapshot.clients)
        }
    }

    public func setBandLock(lte: Set<Int>, nr: Set<Int>) async {
        await apply(success: lte.isEmpty && nr.isEmpty ? "已解除频段锁定" : "频段锁定已应用") {
            try await fetcher.setBandLock(lte: lte, nr: nr)
        }
    }

    public func lockCell(pci: Int, earfcn: Int, is5G: Bool) async {
        await apply(success: "基站锁定已应用") {
            try await fetcher.lockCell(pci: pci, earfcn: earfcn, is5G: is5G)
        }
    }

    public func unlockCells() async {
        await apply(success: "已解除基站锁定") {
            try await fetcher.unlockAllCells()
        }
    }

    public func reboot() async {
        await apply(success: "重启指令已发送", refreshAfterward: false) {
            try await fetcher.rebootDevice()
        }
    }

    private func apply(
        success: String,
        refreshAfterward: Bool = true,
        operation: () async throws -> Void
    ) async {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = nil
        successMessage = nil
        defer { isApplying = false }
        do {
            try await operation()
            successMessage = success
            if refreshAfterward {
                snapshot = try await fetcher.fetchDeviceControlSnapshot()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct F50DeviceControlView: View {
    @StateObject private var model: F50DeviceControlModel
    @State private var pendingReboot = false
    @State private var pendingUSBProtocol: F50USBNetworkProtocol?

    public init(fetcher: F50Fetcher) {
        _model = StateObject(wrappedValue: F50DeviceControlModel(fetcher: fetcher))
    }

    public var body: some View {
        Form {
            Section("移动网络") {
                Toggle("移动数据", isOn: Binding(
                    get: { model.snapshot.isMobileDataEnabled },
                    set: { enabled in Task { await model.setMobileData(enabled) } }
                ))
                .disabled(model.isApplying || model.isLoading)

                Picker("网络模式", selection: Binding(
                    get: { model.snapshot.networkMode },
                    set: { mode in Task { await model.setNetworkMode(mode) } }
                )) {
                    ForEach(F50NetworkMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(model.isApplying || model.isLoading)

                NavigationLink("APN") {
                    F50APNControlView(model: model)
                }
                NavigationLink("流量管理") {
                    F50TrafficManagementView(model: model)
                }
            }

            Section("Wi-Fi") {
                NavigationLink("Wi-Fi 设置") {
                    F50WiFiSettingsView(model: model)
                }
                NavigationLink("Wi-Fi 客户端") {
                    F50WiFiClientControlView(model: model)
                }
            }

            Section("高级移动网络") {
                NavigationLink("频段锁定") {
                    F50BandLockView(model: model)
                }
                NavigationLink("基站锁定") {
                    F50CellLockView(model: model)
                }
            }

            Section {
                Picker("USB 上网协议", selection: Binding(
                    get: { model.snapshot.usbNetworkProtocol },
                    set: { usbProtocol in pendingUSBProtocol = usbProtocol }
                )) {
                    ForEach(F50USBNetworkProtocol.allCases) { usbProtocol in
                        Text(usbProtocol.title).tag(usbProtocol)
                    }
                }
                .disabled(model.isApplying || model.isLoading)

                Button("重启设备", role: .destructive) { pendingReboot = true }
                    .disabled(model.isApplying)
            } header: {
                Text("设备")
            } footer: {
                Text("网络模式、APN、频段锁定、基站锁定可能导致蜂窝连接中断。修改前请确保仍可通过本地 Wi-Fi 或 USB 恢复。")
            }

            if model.isLoading || model.isApplying {
                Section { ProgressView(model.isLoading ? "正在读取设备配置…" : "正在应用设置…") }
            }
            if let message = model.successMessage {
                Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if let message = model.errorMessage {
                Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .navigationTitle("设备控制")
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .confirmationDialog("确认重启 F50？", isPresented: $pendingReboot, titleVisibility: .visible) {
            Button("重启设备", role: .destructive) { Task { await model.reboot() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("设备会暂时离线，当前连接将中断。")
        }
        .confirmationDialog("切换 USB 上网协议？", isPresented: Binding(
            get: { pendingUSBProtocol != nil },
            set: { if !$0 { pendingUSBProtocol = nil } }
        ), titleVisibility: .visible) {
            if let usbProtocol = pendingUSBProtocol {
                Button("切换为 \(usbProtocol.title)") {
                    Task { await model.setUSBNetworkProtocol(usbProtocol) }
                    pendingUSBProtocol = nil
                }
            }
            Button("取消", role: .cancel) { pendingUSBProtocol = nil }
        } message: {
            Text("USB 网络会短暂断开，可能需要重新插拔数据线。")
        }
    }

}

private struct F50TrafficManagementView: View {
    @ObservedObject var model: F50DeviceControlModel
    @State private var draft = F50TrafficManagementSettings()
    @State private var initialized = false

    var body: some View {
        Form {
            Section {
                Toggle("流量管理", isOn: $draft.isEnabled)
                if draft.isEnabled {
                    Toggle("流量清零", isOn: $draft.clearsAutomatically)
                    if draft.clearsAutomatically {
                        HStack {
                            Text("清零日期")
                            Spacer()
                            TextField("清零日期", value: $draft.clearDay, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                            Text("日")
                        }
                    }

                    HStack {
                        Text("已用流量")
                        Spacer()
                        TextField(
                            "已用流量",
                            value: $draft.used,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        Picker("已用单位", selection: $draft.usedUnit) {
                            ForEach(F50TrafficUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("套餐总流量")
                        Spacer()
                        TextField("套餐总流量", value: $draft.limit, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Picker("单位", selection: $draft.unit) {
                            ForEach(F50TrafficUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("流量警戒比例")
                        Spacer()
                        TextField("流量警戒比例", value: $draft.reminderPercentage, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Text("%")
                    }
                }
            }

            Section {
                Button("保存并应用") {
                    Task { await model.saveTrafficManagement(draft) }
                }
                .disabled(model.isApplying || (draft.isEnabled && draft.limit <= 0))
            } footer: {
                Text("可按 80 后台的当前值校准已用流量；达到提醒阈值后设备会提示。")
            }
        }
        .navigationTitle("流量管理")
        .onAppear {
            guard !initialized else { return }
            draft = model.snapshot.trafficManagement
            initialized = true
        }
        .onChange(of: model.snapshot.trafficManagement) { settings in
            guard !model.isApplying else { return }
            draft = settings
        }
    }
}

private struct F50WiFiSettingsView: View {
    @ObservedObject var model: F50DeviceControlModel
    @State private var draft = F50WiFiSettings()
    @State private var initialized = false
    @State private var showsPassword = false
    @State private var pendingSave = false

    private var canSave: Bool {
        if draft.radioMode == .off { return true }
        let ssidLength = draft.ssid.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count
        let passwordLength = draft.password.utf8.count
        return (1...32).contains(ssidLength)
            && (1...32).contains(draft.maximumClients)
            && (draft.securityMode == .open || (8...63).contains(passwordLength))
    }

    var body: some View {
        Form {
            Section("Wi-Fi 开关") {
                Picker("工作频段", selection: $draft.radioMode) {
                    ForEach(F50WiFiRadioMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            if draft.radioMode != .off {
                Section("基本设置") {
                    HStack {
                        Text("网络名称（SSID）")
                        Spacer()
                        TextField("网络名称（SSID）", text: $draft.ssid)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 220)
                    }
                    Toggle("广播网络名称（SSID）", isOn: $draft.broadcastsSSID)
                    Picker("安全模式", selection: $draft.securityMode) {
                        ForEach(F50WiFiSecurityMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    if draft.securityMode != .open {
                        HStack {
                            Text("密码")
                            Spacer()
                            if showsPassword {
                                TextField("密码", text: $draft.password)
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 220)
                            } else {
                                SecureField("密码", text: $draft.password)
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 220)
                            }
                        }
                        Toggle("显示密码", isOn: $showsPassword)
                    }
                    HStack {
                        Text("最大接入数")
                        Spacer()
                        TextField("最大接入数", value: $draft.maximumClients, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                    }
                }
            }

            Section {
                Button("保存并应用") { pendingSave = true }
                    .disabled(model.isApplying || !canSave)
            } footer: {
                Text("修改频段、网络名称或密码会中断当前 Wi-Fi 连接，请使用新配置重新连接。")
            }
        }
        .navigationTitle("Wi-Fi 设置")
        .onAppear { initializeDraft() }
        .onChange(of: model.snapshot.wifi) { _ in initializeDraft(force: true) }
        .alert("确认修改 Wi-Fi 设置？", isPresented: $pendingSave) {
            Button("保存并应用", role: .destructive) {
                Task { await model.saveWiFi(draft) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前连接可能立即断开；关闭 Wi-Fi 后请通过 USB 或设备后台恢复。")
        }
    }

    private func initializeDraft(force: Bool = false) {
        guard force || !initialized else { return }
        draft = model.snapshot.wifi
        initialized = true
    }
}

private struct F50APNControlView: View {
    @ObservedObject var model: F50DeviceControlModel
    @State private var draft = F50APNSettings()
    @State private var initialized = false
    @State private var pendingSave = false

    var body: some View {
        Form {
            Section {
                Toggle("自动 APN", isOn: Binding(
                    get: { draft.isAutomatic },
                    set: { draft.isAutomatic = $0 }
                ))
            }

            if !draft.isAutomatic {
                Section("APN") {
                    Picker("PDP 类型", selection: $draft.pdpType) {
                        Text("IPv4").tag("IP")
                        Text("IPv6").tag("IPv6")
                        Text("IPv4 / IPv6").tag("IPv4v6")
                    }
                    TextField("配置文件名称", text: $draft.profileName)
                    TextField("APN", text: $draft.apn)
                    Picker("鉴权方式", selection: $draft.authentication) {
                        Text("无").tag("none")
                        Text("CHAP").tag("chap")
                        Text("PAP").tag("pap")
                    }
                    TextField("用户名", text: $draft.username)
                    SecureField("密码", text: $draft.password)
                }
            }

            Section {
                Button("保存并应用") { pendingSave = true }
                    .disabled(model.isApplying || (!draft.isAutomatic && (draft.profileName.isEmpty || draft.apn.isEmpty)))
            }
        }
        .navigationTitle("APN")
        .onAppear { initializeDraft() }
        .onChange(of: model.snapshot.apn) { _ in initializeDraft(force: true) }
        .confirmationDialog("确认修改 APN？", isPresented: $pendingSave, titleVisibility: .visible) {
            Button("保存并应用", role: .destructive) {
                Task {
                    if draft.isAutomatic { await model.useAutomaticAPN() }
                    else { await model.saveAPN(draft) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("错误配置可能导致蜂窝数据无法连接。")
        }
    }

    private func initializeDraft(force: Bool = false) {
        guard force || !initialized else { return }
        draft = model.snapshot.apn
        initialized = true
    }
}

private struct F50WiFiClientControlView: View {
    @ObservedObject var model: F50DeviceControlModel
    @State private var pendingClient: F50WiFiClient?

    var body: some View {
        List {
            Section("已连接") {
                ForEach(model.snapshot.clients.filter { !$0.isBlocked }) { client in
                    clientRow(client, action: "踢出") { pendingClient = client }
                }
            }
            Section("黑名单") {
                ForEach(model.snapshot.clients.filter(\.isBlocked)) { client in
                    clientRow(client, action: "解除") {
                        Task { await model.setClientBlocked(client, blocked: false) }
                    }
                }
            }
        }
        .navigationTitle("Wi-Fi 客户端")
        .confirmationDialog("踢出并拉黑该设备？", isPresented: Binding(
            get: { pendingClient != nil },
            set: { if !$0 { pendingClient = nil } }
        ), titleVisibility: .visible) {
            Button("踢出设备", role: .destructive) {
                guard let client = pendingClient else { return }
                pendingClient = nil
                Task { await model.setClientBlocked(client, blocked: true) }
            }
            Button("取消", role: .cancel) { pendingClient = nil }
        } message: {
            Text("设备会加入黑名单，解除前无法重新连接。")
        }
    }

    @ViewBuilder
    private func clientRow(_ client: F50WiFiClient, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(client.name.isEmpty ? "未知设备" : client.name)
                Text("\(client.ipAddress)  \(client.macAddress)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action, role: client.isBlocked ? nil : .destructive, action: perform)
                .disabled(model.isApplying)
        }
    }
}

private struct F50BandLockView: View {
    @ObservedObject var model: F50DeviceControlModel
    @State private var lteBands: Set<Int> = []
    @State private var nrBands: Set<Int> = []
    @State private var pendingApply = false

    private let commonLTEBands = [1, 3, 5, 8, 34, 38, 39, 40, 41]
    private let commonNRBands = [1, 5, 8, 28, 41, 78]

    var body: some View {
        Form {
            Section("4G 常用频段") {
                ForEach(commonLTEBands, id: \.self) { band in
                    Toggle("B\(band)", isOn: bandBinding(band, in: $lteBands))
                }
            }
            Section("5G 常用频段") {
                ForEach(commonNRBands, id: \.self) { band in
                    Toggle("n\(band)", isOn: bandBinding(band, in: $nrBands))
                }
            }
            Section {
                Button("应用频段锁定") { pendingApply = true }
                    .disabled(model.isApplying || (lteBands.isEmpty && nrBands.isEmpty))
                Button("解除全部频段锁定", role: .destructive) {
                    Task { await model.setBandLock(lte: [], nr: []) }
                }
                .disabled(model.isApplying)
            } footer: {
                Text("仅接受逗号分隔的频段数字。解除锁定会恢复设备支持的全部频段。")
            }
        }
        .navigationTitle("频段锁定")
        .onAppear {
            lteBands = model.snapshot.lockedLTEBands
            nrBands = model.snapshot.lockedNRBands
        }
        .confirmationDialog("确认锁定频段？", isPresented: $pendingApply, titleVisibility: .visible) {
            Button("应用锁定", role: .destructive) {
                Task { await model.setBandLock(lte: lteBands, nr: nrBands) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("错误频段可能导致设备无法入网。")
        }
    }

    private func bandBinding(_ band: Int, in bands: Binding<Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { bands.wrappedValue.contains(band) },
            set: { isSelected in
                if isSelected {
                    bands.wrappedValue.insert(band)
                } else {
                    bands.wrappedValue.remove(band)
                }
            }
        )
    }
}

private struct F50CellLockView: View {
    @ObservedObject var model: F50DeviceControlModel
    @State private var selectedCell: F50NeighborCell?
    @State private var pendingLock = false

    var body: some View {
        Form {
            Section("当前基站") {
                if let currentCell = model.snapshot.currentCell {
                    selectableCellRow(currentCell)
                } else {
                    Text("未读取到当前基站信息，请刷新设备控制后重试。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("已扫描基站") {
                if model.snapshot.neighborCells.isEmpty {
                    Text("未读取到扫描结果，请刷新设备控制后重试。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.snapshot.neighborCells) { cell in
                        selectableCellRow(cell)
                    }
                }
            }
            Section {
                Button("应用基站锁定") { pendingLock = true }
                    .disabled(model.isApplying || selectedCell == nil)
                Button("解除全部基站锁定", role: .destructive) {
                    Task { await model.unlockCells() }
                }
                .disabled(model.isApplying)
            } footer: {
                Text("选择扫描到的基站后再锁定。锁定可能导致当前连接中断，请保留本地 Wi-Fi 或 USB 恢复路径。")
            }
        }
        .navigationTitle("基站锁定")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await model.refresh()
            }
        }
        .alert("确认锁定基站？", isPresented: $pendingLock) {
            Button("应用锁定", role: .destructive) {
                guard let selectedCell else { return }
                Task { await model.lockCell(pci: selectedCell.pci, earfcn: selectedCell.earfcn, is5G: selectedCell.is5G) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("错误的小区参数可能导致设备无信号。")
        }
    }

    private func selectableCellRow(_ cell: F50NeighborCell) -> some View {
        Button {
            selectedCell = cell
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .opacity(isSelected(cell) ? 1 : 0)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cell.radioTitle) \(cell.bandTitle) · EARFCN \(cell.earfcn) · PCI \(cell.pci)")
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 8) {
                        signalMetric("RSRP", value: cell.rsrp, thresholds: [-85, -95, -105])
                        signalMetric("SINR", value: cell.sinr, thresholds: [20, 13, 3])
                        signalMetric("RSRQ", value: cell.rsrq, thresholds: [-10, -15, -20])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ cell: F50NeighborCell) -> Bool {
        selectedCell?.pci == cell.pci && selectedCell?.earfcn == cell.earfcn && selectedCell?.is5G == cell.is5G
    }

    private func signalMetric(_ title: String, value: String, thresholds: [Double]) -> some View {
        let quality = signalQuality(value, thresholds: thresholds)
        return HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 2)
                .fill(quality.color)
                .frame(width: CGFloat(36 * quality.ratio), height: 3)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .foregroundStyle(quality.color)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption2.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signalQuality(_ value: String, thresholds: [Double]) -> (label: String, color: Color, ratio: Double) {
        let number = Double(value.replacingOccurrences(of: "dBm", with: "").replacingOccurrences(of: "dB", with: "").trimmingCharacters(in: .whitespaces))
        guard let number else { return ("—", .secondary, 0) }
        if number >= thresholds[0] { return ("极佳", .green, 1) }
        if number >= thresholds[1] { return ("良好", .blue, 0.75) }
        if number >= thresholds[2] { return ("一般", .orange, 0.5) }
        return ("较差", .red, 0.25)
    }
}

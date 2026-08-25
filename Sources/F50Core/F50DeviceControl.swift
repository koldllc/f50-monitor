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

public struct F50WiFiClient: Identifiable, Hashable, Sendable {
    public let name: String
    public let ipAddress: String
    public let macAddress: String
    public let isWired: Bool
    public let isBlocked: Bool

    public var id: String { macAddress.lowercased() }
}

public struct F50APNSettings: Equatable, Sendable {
    public var index: Int
    public var profileName: String
    public var apn: String
    public var username: String
    public var password: String
    public var authentication: String
    public var pdpType: String
    public var primaryDNS: String
    public var secondaryDNS: String
    public var isAutomatic: Bool

    public init(
        index: Int = 0,
        profileName: String = "",
        apn: String = "",
        username: String = "",
        password: String = "",
        authentication: String = "none",
        pdpType: String = "IPv4v6",
        primaryDNS: String = "",
        secondaryDNS: String = "",
        isAutomatic: Bool = true
    ) {
        self.index = index
        self.profileName = profileName
        self.apn = apn
        self.username = username
        self.password = password
        self.authentication = authentication
        self.pdpType = pdpType
        self.primaryDNS = primaryDNS
        self.secondaryDNS = secondaryDNS
        self.isAutomatic = isAutomatic
    }
}

public struct F50DeviceControlSnapshot: Sendable {
    public var isMobileDataEnabled: Bool
    public var networkMode: F50NetworkMode
    public var apn: F50APNSettings
    public var clients: [F50WiFiClient]
    public var accessControlMode: String
    public var lockedLTEBands: Set<Int>
    public var lockedNRBands: Set<Int>

    public init(
        isMobileDataEnabled: Bool = false,
        networkMode: F50NetworkMode = .automatic,
        apn: F50APNSettings = F50APNSettings(),
        clients: [F50WiFiClient] = [],
        accessControlMode: String = "2",
        lockedLTEBands: Set<Int> = [],
        lockedNRBands: Set<Int> = []
    ) {
        self.isMobileDataEnabled = isMobileDataEnabled
        self.networkMode = networkMode
        self.apn = apn
        self.clients = clients
        self.accessControlMode = accessControlMode
        self.lockedLTEBands = lockedLTEBands
        self.lockedNRBands = lockedNRBands
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

    public func saveAPN(_ settings: F50APNSettings) async {
        await apply(success: "APN 与 DNS 已保存") {
            try await fetcher.saveAPNSettings(settings)
        }
    }

    public func useAutomaticAPN() async {
        await apply(success: "已恢复自动 APN") {
            try await fetcher.useAutomaticAPN()
        }
    }

    public func setClientBlocked(_ client: F50WiFiClient, blocked: Bool) async {
        await apply(success: blocked ? "设备已加入黑名单" : "设备已解除黑名单") {
            try await fetcher.setWiFiClient(client, blocked: blocked, currentClients: snapshot.clients)
        }
    }

    public func setBandLock(lte: Set<Int>, nr: Set<Int>) async {
        await apply(success: lte.isEmpty && nr.isEmpty ? "已解除 Band Lock" : "Band Lock 已应用") {
            try await fetcher.setBandLock(lte: lte, nr: nr)
        }
    }

    public func lockCell(pci: Int, earfcn: Int, is5G: Bool) async {
        await apply(success: "Cell Lock 已应用") {
            try await fetcher.lockCell(pci: pci, earfcn: earfcn, is5G: is5G)
        }
    }

    public func unlockCells() async {
        await apply(success: "已解除 Cell Lock") {
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

    public init(fetcher: F50Fetcher) {
        _model = StateObject(wrappedValue: F50DeviceControlModel(fetcher: fetcher))
    }

    public var body: some View {
        Form {
            Section("蜂窝网络") {
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
            }

            Section("配置与设备") {
                NavigationLink("APN 与 DNS") {
                    F50APNControlView(model: model)
                }
                NavigationLink("Wi-Fi 客户端") {
                    F50WiFiClientControlView(model: model)
                }
            }

            Section("高级蜂窝控制") {
                NavigationLink("Band Lock") {
                    F50BandLockView(model: model)
                }
                NavigationLink("Cell Lock") {
                    F50CellLockView(model: model)
                }
            }

            Section {
                Button("重启设备", role: .destructive) { pendingReboot = true }
                    .disabled(model.isApplying)
            } footer: {
                Text("网络模式、APN、Band Lock、Cell Lock 可能导致蜂窝连接中断。修改前请确保仍可通过本地 Wi-Fi 或 USB 恢复。")
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
                    TextField("配置名称", text: $draft.profileName)
                    TextField("APN", text: $draft.apn)
                    TextField("用户名（可选）", text: $draft.username)
                    SecureField("密码（可选）", text: $draft.password)
                    Picker("鉴权方式", selection: $draft.authentication) {
                        Text("无").tag("none")
                        Text("CHAP").tag("chap")
                        Text("PAP").tag("pap")
                    }
                    Picker("PDP 类型", selection: $draft.pdpType) {
                        Text("IPv4").tag("IP")
                        Text("IPv6").tag("IPv6")
                        Text("IPv4 / IPv6").tag("IPv4v6")
                    }
                }
                Section("DNS（随 APN 生效）") {
                    TextField("首选 DNS，留空为自动", text: $draft.primaryDNS)
                    TextField("备用 DNS，留空为自动", text: $draft.secondaryDNS)
                }
            }

            Section {
                Button("保存并应用") { pendingSave = true }
                    .disabled(model.isApplying || (!draft.isAutomatic && (draft.profileName.isEmpty || draft.apn.isEmpty)))
            } footer: {
                Text("这里配置的是蜂窝 APN 使用的 DNS，不是 Wi-Fi 热点 DHCP 下发的 DNS。")
            }
        }
        .navigationTitle("APN 与 DNS")
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
    @State private var lteBands = ""
    @State private var nrBands = ""
    @State private var pendingApply = false

    var body: some View {
        Form {
            Section("锁定频段") {
                TextField("4G Band，例如 1,3,8", text: $lteBands)
                TextField("5G Band，例如 41,78", text: $nrBands)
            }
            Section {
                Button("应用 Band Lock") { pendingApply = true }
                    .disabled(model.isApplying || (parsedLTE.isEmpty && parsedNR.isEmpty))
                Button("解除全部 Band Lock", role: .destructive) {
                    Task { await model.setBandLock(lte: [], nr: []) }
                }
                .disabled(model.isApplying)
            } footer: {
                Text("仅接受逗号分隔的频段数字。解除锁定会恢复设备支持的全部频段。")
            }
        }
        .navigationTitle("Band Lock")
        .onAppear {
            lteBands = model.snapshot.lockedLTEBands.sorted().map(String.init).joined(separator: ",")
            nrBands = model.snapshot.lockedNRBands.sorted().map(String.init).joined(separator: ",")
        }
        .confirmationDialog("确认锁定频段？", isPresented: $pendingApply, titleVisibility: .visible) {
            Button("应用锁定", role: .destructive) {
                Task { await model.setBandLock(lte: parsedLTE, nr: parsedNR) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("错误频段可能导致设备无法入网。")
        }
    }

    private var parsedLTE: Set<Int> { parseBands(lteBands) }
    private var parsedNR: Set<Int> { parseBands(nrBands) }
    private func parseBands(_ value: String) -> Set<Int> {
        Set(value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...1024).contains($0) })
    }
}

private struct F50CellLockView: View {
    @ObservedObject var model: F50DeviceControlModel
    @State private var is5G = true
    @State private var pci = ""
    @State private var earfcn = ""
    @State private var pendingLock = false

    var body: some View {
        Form {
            Section("目标小区") {
                Picker("网络类型", selection: $is5G) {
                    Text("5G").tag(true)
                    Text("4G").tag(false)
                }
                TextField("PCI", text: $pci)
                TextField("EARFCN / NR-ARFCN", text: $earfcn)
            }
            Section {
                Button("应用 Cell Lock") { pendingLock = true }
                    .disabled(model.isApplying || pciValue == nil || earfcnValue == nil)
                Button("解除全部 Cell Lock", role: .destructive) {
                    Task { await model.unlockCells() }
                }
                .disabled(model.isApplying)
            } footer: {
                Text("5G 使用 RAT 16，4G 使用 RAT 12。请先从设备当前小区信息确认 PCI 与频点。")
            }
        }
        .navigationTitle("Cell Lock")
        .confirmationDialog("确认锁定小区？", isPresented: $pendingLock, titleVisibility: .visible) {
            Button("应用锁定", role: .destructive) {
                guard let pciValue, let earfcnValue else { return }
                Task { await model.lockCell(pci: pciValue, earfcn: earfcnValue, is5G: is5G) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("错误的小区参数可能导致设备无信号。")
        }
    }

    private var pciValue: Int? { Int(pci).flatMap { (0...1007).contains($0) ? $0 : nil } }
    private var earfcnValue: Int? { Int(earfcn).flatMap { $0 > 0 ? $0 : nil } }
}

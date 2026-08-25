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
    public var currentCell: F50NeighborCell?
    public var neighborCells: [F50NeighborCell]

    public init(
        isMobileDataEnabled: Bool = false,
        networkMode: F50NetworkMode = .automatic,
        apn: F50APNSettings = F50APNSettings(),
        clients: [F50WiFiClient] = [],
        accessControlMode: String = "2",
        lockedLTEBands: Set<Int> = [],
        lockedNRBands: Set<Int> = [],
        currentCell: F50NeighborCell? = nil,
        neighborCells: [F50NeighborCell] = []
    ) {
        self.isMobileDataEnabled = isMobileDataEnabled
        self.networkMode = networkMode
        self.apn = apn
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
                NavigationLink("频段锁定") {
                    F50BandLockView(model: model)
                }
                NavigationLink("基站锁定") {
                    F50CellLockView(model: model)
                }
            }

            Section {
                Button("重启设备", role: .destructive) { pendingReboot = true }
                    .disabled(model.isApplying)
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
        .confirmationDialog("确认锁定基站？", isPresented: $pendingLock, titleVisibility: .visible) {
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
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cell.radioTitle) \(cell.bandTitle) · EARFCN \(cell.earfcn) · PCI \(cell.pci)")
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 8) {
                        signalMetric("RSRP", value: cell.rsrp, thresholds: [-85, -95, -105])
                        signalMetric("RSRQ", value: cell.rsrq, thresholds: [-10, -15, -20])
                        signalMetric("SINR", value: cell.sinr, thresholds: [20, 13, 3])
                    }
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .opacity(isSelected(cell) ? 1 : 0)
                    .frame(width: 20)
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
        }
        .font(.caption2.weight(.medium))
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

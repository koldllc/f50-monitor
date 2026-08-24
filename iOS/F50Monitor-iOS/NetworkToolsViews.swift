import AudioToolbox
import Combine
import F50Core
import SwiftUI
import UIKit

private extension String {
    var f50NumericValue: Double? {
        let allowed = CharacterSet(charactersIn: "-0123456789.")
        let value = unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        return Double(value)
    }
}

private extension TelemetrySample {
    init(status: F50Status, timestamp: Date = Date(), latencyMilliseconds: Double? = nil, packetLossPercent: Double? = nil) {
        let cellularConnected: Bool?
        switch status.pppStatus {
        case "已连接": cellularConnected = true
        case "未连接": cellularConnected = false
        default: cellularConnected = nil
        }
        self.init(
            timestamp: timestamp,
            online: status.isOnline,
            cellularConnected: cellularConnected,
            networkType: status.networkType,
            rsrp: status.rsrp.f50NumericValue,
            rsrq: status.rsrq.f50NumericValue,
            snr: status.snr.f50NumericValue,
            band: status.currentBands.isEmpty ? nil : status.currentBands,
            temperature: status.temperature > 0 ? status.temperature : nil,
            downloadBytesPerSecond: status.dlSpeed,
            uploadBytesPerSecond: status.ulSpeed,
            latencyMilliseconds: latencyMilliseconds,
            packetLossPercent: packetLossPercent,
            pci: status.pci,
            cellId: status.cellId,
            tac: status.tac,
            rsrpSource: status.rsrpSource,
            rsrqSource: status.rsrqSource,
            snrSource: status.snrSource,
            snrKind: status.snrMetricKind ?? .unknown,
            dataAgeSeconds: max(0, timestamp.timeIntervalSince(status.lastUpdated)),
            localConnectionError: status.isOnline ? nil : status.errorMessage
        )
    }
}

@MainActor
private final class SignalLabSession: ObservableObject {
    @Published private(set) var insight: LiveSignalInsight
    @Published private(set) var locations: [LocationReport] = []
    @Published private(set) var isTesting = false
    @Published private(set) var progress = 0.0
    @Published var locationName = "窗边"
    @Published var duration: TimeInterval = 30
    @Published var soundEnabled = true

    private let engine = NetworkInsightEngine()
    private let locationsDefaultsKey = "F50_iOS_SignalLabLocations_v1"
    private var locationSamples: [TelemetrySample] = []
    private var startedAt: Date?
    private var nextSoundAt = Date.distantPast

    init() {
        insight = engine.liveInsight
        if let data = UserDefaults.standard.data(forKey: locationsDefaultsKey),
           let stored = try? JSONDecoder().decode([LocationReport].self, from: data) {
            locations = stored
        }
    }

    func receive(_ status: F50Status, at now: Date = Date()) {
        let sample = TelemetrySample(status: status, timestamp: now)
        insight = engine.append(sample)
        if isTesting {
            locationSamples.append(sample)
            updateProgress(at: now)
        }
    }

    func start() {
        let cleanName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        locationName = cleanName.isEmpty ? "位置 \(locations.count + 1)" : cleanName
        locationSamples.removeAll(keepingCapacity: true)
        startedAt = Date()
        progress = 0
        nextSoundAt = .distantPast
        isTesting = true
    }

    func tick(at now: Date = Date()) {
        guard isTesting else { return }
        updateProgress(at: now)
        guard soundEnabled, now >= nextSoundAt, insight.score.confidence > 0 else { return }
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let scoreRatio = Double(insight.score.value) / 100
        nextSoundAt = now.addingTimeInterval(max(0.32, 1.35 - scoreRatio))
    }

    func finish() {
        guard isTesting else { return }
        isTesting = false
        progress = 1
        if !locationSamples.isEmpty {
            let stableSamples: [TelemetrySample]
            if let startedAt {
                stableSamples = locationSamples.filter { $0.timestamp.timeIntervalSince(startedAt) >= 5 }
            } else {
                stableSamples = locationSamples
            }
            let report = engine.makeLocationReport(
                name: locationName,
                samples: stableSamples.isEmpty ? locationSamples : stableSamples
            )
            locations.removeAll { $0.name == report.name }
            locations.append(report)
            persistLocations()
        }
        locationSamples.removeAll()
        startedAt = nil
    }

    func removeLocations(at offsets: IndexSet) {
        let sorted = comparison.locations
        let names = Set(offsets.compactMap { sorted.indices.contains($0) ? sorted[$0].name : nil })
        locations.removeAll { names.contains($0.name) }
        persistLocations()
    }

    var comparison: LocationComparison { engine.compareLocations(locations) }

    private func updateProgress(at now: Date) {
        guard let startedAt else { return }
        progress = min(1, max(0, now.timeIntervalSince(startedAt) / duration))
        if progress >= 1 { finish() }
    }

    private func persistLocations() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        UserDefaults.standard.set(data, forKey: locationsDefaultsKey)
    }
}

struct SignalLabView: View {
    @ObservedObject var fetcher: F50Fetcher
    @StateObject private var session = SignalLabSession()
    @State private var shareImage: UIImage?
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(session.insight.score.value)")
                            .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(scoreColor)
                        Text("分")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: trendSymbol)
                            .font(.title2.bold())
                            .foregroundStyle(trendColor)
                    }

                    Text(session.insight.recommendation)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    ProgressView(value: Double(session.insight.score.value), total: 100)
                        .tint(scoreColor)

                    HStack(spacing: 8) {
                        scoreChip("信号强度", session.insight.score.strengthScore)
                        scoreChip("干扰质量", session.insight.score.interferenceScore)
                        scoreChip("稳定性", session.insight.sampleCount >= 4 ? session.insight.stabilityScore : nil)
                    }

                    HStack {
                        metric("RSRP", fetcher.status.rsrp)
                        Divider()
                        metric(session.insight.noiseMetricKind.rawValue, fetcher.status.snr)
                        Divider()
                        metric("RSRQ", fetcher.status.rsrq)
                    }

                    HStack(spacing: 8) {
                        Label(fetcher.status.networkType, systemImage: "antenna.radiowaves.left.and.right")
                        if !fetcher.status.currentBands.isEmpty {
                            Text(fetcher.status.currentBands)
                        }
                        if let pci = fetcher.status.pci {
                            Text("PCI \(pci)")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    if fetcher.status.cellId != nil || fetcher.status.tac != nil {
                        HStack(spacing: 10) {
                            if let cellId = fetcher.status.cellId { Text("Cell ID \(cellId)") }
                            if let tac = fetcher.status.tac { Text("TAC \(tac)") }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }

                    if let source = fetcher.status.cellIdentitySource {
                        Text("小区来源：\(source)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(dataQualityText)
                        .font(.caption2)
                        .foregroundStyle(session.insight.score.isStale ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                Text("评分依据最近采集的 RSRP、SINR/SNR 与 RSRQ；指标缺失或数据陈旧时会降低可信度。固件未提供 PCI、Cell ID 或 TAC 时不会推测。")
            }

            Section {
                TextField("位置名称", text: $session.locationName)
                    .disabled(session.isTesting)

                HStack {
                    ForEach(["窗边", "桌面", "阳台"], id: \.self) { name in
                        Button(name) { session.locationName = name }
                            .buttonStyle(.bordered)
                            .disabled(session.isTesting)
                    }
                }

                Picker("测试时长", selection: $session.duration) {
                    Text("30 秒").tag(30.0)
                    Text("60 秒").tag(60.0)
                }
                .pickerStyle(.segmented)
                .disabled(session.isTesting)

                Toggle("声音与触觉提示", isOn: $session.soundEnabled)

                if session.isTesting {
                    ProgressView(value: session.progress)
                    Button("提前结束并保存") { session.finish() }
                } else {
                    Button {
                        session.start()
                    } label: {
                        Label("开始测试当前位置", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.insight.score.confidence < 0.5)
                }
            } header: {
                Text("找信号最佳位置")
            } footer: {
                Text("当前版本比较 F50 上报的信号、5G 在线率、切换次数与实际活动速率；不会主动下载测速文件或消耗额外测试流量。")
            }

            if !session.locations.isEmpty {
                Section {
                    ForEach(session.comparison.locations, id: \.name) { location in
                        LocationResultRow(location: location, isBest: location.name == session.comparison.bestLocationName)
                    }
                    .onDelete(perform: session.removeLocations)

                    if session.locations.count >= 2 {
                        Button {
                            shareImage = SignalShareRenderer.render(session.comparison)
                        } label: {
                            Label("生成并分享测试图", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text(session.comparison.bestLocationName.map { "最佳位置：\($0)" } ?? "位置结果")
                }
            }
        }
        .navigationTitle("Signal Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.receive(fetcher.status) }
        .onReceive(fetcher.$status) { session.receive($0) }
        .onReceive(clock) { session.tick(at: $0) }
        .sheet(isPresented: Binding(
            get: { shareImage != nil },
            set: { if !$0 { shareImage = nil } }
        )) {
            if let shareImage {
                ActivityViewController(items: [shareImage])
            }
        }
    }

    private var scoreColor: Color {
        switch session.insight.score.value {
        case 80...: return .green
        case 60...: return .blue
        case 40...: return .orange
        default: return .red
        }
    }

    private var trendSymbol: String {
        switch session.insight.trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .insufficient: return "ellipsis"
        }
    }

    private var trendColor: Color {
        switch session.insight.trend {
        case .up: return .green
        case .down: return .orange
        case .stable, .insufficient: return .secondary
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.bold).monospacedDigit()).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func scoreChip(_ title: String, _ value: Int?) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { String($0) } ?? "--")
                .font(.subheadline.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var dataQualityText: String {
        let confidence = Int((session.insight.score.confidence * 100).rounded())
        let sources = Int((session.insight.score.sourceCoverage * 100).rounded())
        let sourceNames = [fetcher.status.rsrpSource, fetcher.status.snrSource, fetcher.status.rsrqSource]
            .compactMap { $0 }
            .joined(separator: " / ")
        let suffix = sourceNames.isEmpty ? "来源未标记" : sourceNames
        return "可信度 \(confidence)% · 来源完整度 \(sources)% · \(suffix)"
    }
}

private struct LocationResultRow: View {
    let location: LocationReport
    let isBest: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((isBest ? Color.green : .secondary).opacity(0.12))
                Text("\(location.score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isBest ? .green : .primary)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(location.name).font(.headline)
                    if isBest {
                        Text("最佳").font(.caption2.bold()).foregroundStyle(.green)
                    }
                }
                Text("5G \(Int((location.fiveGOnlineRate * 100).rounded()))% · 切换 \(location.switchCount) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("活动速率 ↓ \(F50Status.formatSpeed(location.averageDownloadBytesPerSecond))  ↑ \(F50Status.formatSpeed(location.averageUploadBytesPerSecond))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private final class NetworkDoctorSession: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress = 0.0
    @Published private(set) var report: DoctorReport

    private let engine = NetworkInsightEngine()
    private let reportDefaultsKey = "F50_iOS_NetworkDoctorLatestReport_v1"
    private var startedAt: Date?
    private var lastProbeAt = Date.distantPast
    private var probeInFlight = false
    let duration: TimeInterval = 600

    init() {
        if let data = UserDefaults.standard.data(forKey: reportDefaultsKey),
           let stored = try? JSONDecoder().decode(DoctorReport.self, from: data) {
            report = stored
        } else {
            report = engine.diagnose()
        }
    }

    func start(with status: F50Status) {
        engine.reset()
        startedAt = Date()
        isRunning = true
        progress = 0
        receive(status)
    }

    func receive(_ status: F50Status, at now: Date = Date()) {
        guard isRunning else { return }
        _ = engine.append(TelemetrySample(status: status, timestamp: now))
        report = engine.diagnose()
        update(at: now)
    }

    func tick(at now: Date = Date()) {
        guard isRunning else { return }
        update(at: now)
    }

    func probeConnectivity(with status: F50Status, at now: Date = Date()) async {
        guard isRunning, !probeInFlight, now.timeIntervalSince(lastProbeAt) >= 5 else { return }
        probeInFlight = true
        lastProbeAt = now
        defer { probeInFlight = false }

        var measuredLatency: Double?
        for address in ["https://cp.cloudflare.com/generate_204", "https://captive.apple.com/hotspot-detect.html"] {
            guard let url = URL(string: address) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let started = Date()
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode)
            else { continue }
            measuredLatency = Date().timeIntervalSince(started) * 1_000
            break
        }
        receive(status, at: Date(), latencyMilliseconds: measuredLatency, packetLossPercent: measuredLatency == nil ? 100 : 0)
    }

    func finish() {
        guard isRunning else { return }
        isRunning = false
        report = engine.diagnose()
        if let data = try? JSONEncoder().encode(report) {
            UserDefaults.standard.set(data, forKey: reportDefaultsKey)
        }
        startedAt = nil
    }

    private func receive(_ status: F50Status, at now: Date, latencyMilliseconds: Double?, packetLossPercent: Double?) {
        guard isRunning else { return }
        _ = engine.append(TelemetrySample(status: status, timestamp: now, latencyMilliseconds: latencyMilliseconds, packetLossPercent: packetLossPercent))
        report = engine.diagnose()
        update(at: now)
    }

    private func update(at now: Date) {
        guard let startedAt else { return }
        progress = min(1, now.timeIntervalSince(startedAt) / duration)
        if progress >= 1 { finish() }
    }
}

struct NetworkDoctorView: View {
    @ObservedObject var fetcher: F50Fetcher
    @StateObject private var session = NetworkDoctorSession()
    @State private var exportReport: String?
    @State private var includeSensitiveData = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: session.isRunning ? "waveform.path.ecg" : "stethoscope")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(session.isRunning ? .green : .blue)

                    Text(session.isRunning ? "正在记录网络状态" : "10 分钟主动诊断")
                        .font(.title3.bold())

                    Text(session.isRunning ? "请保持 F50 Monitor 在前台，完成后会自动分析。" : "按时间关联掉线、切换、温度、SINR 波动与丢包，分析网络异常的可能原因。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if session.isRunning {
                        ProgressView(value: session.progress)
                        Button("提前结束并分析") { session.finish() }
                    } else {
                        Button {
                            session.start(with: fetcher.status)
                        } label: {
                            Label("开始诊断", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!fetcher.status.isOnline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                Text("仅在前台采样。每 5 秒发送一次极小的公网连通性请求以估算延迟与丢包，不下载测速文件。")
            }

            if session.report.sampleCount > 0 {
                Section("诊断摘要") {
                    DoctorSummaryRow(title: "采样", value: "\(session.report.sampleCount) 次")
                    DoctorSummaryRow(title: "5G 在线率", value: "\(Int((session.report.fiveGOnlineRate * 100).rounded()))%")
                    DoctorSummaryRow(title: "网络切换", value: "\(session.report.switchSummary.total) 次")
                    DoctorSummaryRow(title: "频段/小区变化", value: "\(session.report.cellularChanges?.count ?? 0) 次")
                    DoctorSummaryRow(title: "5G → LTE", value: "\(session.report.switchSummary.fiveGToLTE) 次")
                    DoctorSummaryRow(title: "LTE → 5G", value: "\(session.report.switchSummary.lteToFiveG) 次")
                }

                Section("可能原因") {
                    if session.report.findings.isEmpty {
                        Label("当前采样未发现明显异常", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(Array(session.report.findings.enumerated()), id: \.offset) { _, finding in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(finding.title).font(.headline)
                                Spacer()
                                Text(confidenceText(finding.confidence))
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                            }
                            Text(finding.summary).font(.subheadline)
                            ForEach(finding.evidence, id: \.self) { evidence in
                                Label(evidence, systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(finding.counterEvidence ?? [], id: \.self) { evidence in
                                Label(evidence, systemImage: "minus.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                if let counterEvidence = session.report.counterEvidence, !counterEvidence.isEmpty {
                    Section("反证与较低可能性") {
                        ForEach(counterEvidence, id: \.self) { evidence in
                            Label(evidence, systemImage: "checkmark.shield")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let timeline = session.report.timeline, !timeline.isEmpty {
                    Section("关联时间线") {
                        ForEach(Array(timeline.reversed().enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.summary).font(.subheadline.weight(.semibold))
                                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Toggle("包含 Cell ID、PCI、TAC 与设备地址", isOn: $includeSensitiveData)
                    Button {
                        exportReport = session.report.exportMarkdown(
                            deviceAddress: F50Configuration.displayAddress(from: fetcher.baseURLString),
                            includeSensitiveData: includeSensitiveData
                        )
                    } label: {
                        Label("导出并分享", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("导出诊断报告")
                } footer: {
                    if includeSensitiveData {
                        Text("当前导出会包含敏感设备标识，请确认分享对象。")
                            .foregroundStyle(.orange)
                    } else {
                        Text("默认隐藏 Cell ID、PCI、TAC 和设备地址。")
                    }
                }
            }
        }
        .navigationTitle("Network Doctor")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(fetcher.$status) { session.receive($0) }
        .onReceive(clock) {
            session.tick(at: $0)
            Task { await session.probeConnectivity(with: fetcher.status, at: $0) }
        }
        .sheet(isPresented: Binding(
            get: { exportReport != nil },
            set: { if !$0 { exportReport = nil } }
        )) {
            if let exportReport { ActivityViewController(items: [exportReport]) }
        }
    }

    private func confidenceText(_ value: Double) -> String {
        switch value {
        case 0.75...: return "可信度较高"
        case 0.5...: return "可信度中等"
        default: return "仅供参考"
        }
    }

}

private struct DoctorSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).font(.body.weight(.semibold).monospacedDigit())
        }
    }
}

@MainActor
private enum SignalShareRenderer {
    static func render(_ comparison: LocationComparison) -> UIImage? {
        let renderer = ImageRenderer(
            content: SignalShareCard(comparison: comparison)
                .frame(width: 540, height: 720)
        )
        renderer.scale = 2
        return renderer.uiImage
    }
}

private struct SignalShareCard: View {
    let comparison: LocationComparison

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.075)
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("F50 SIGNAL TEST")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.cyan)
                    Text("最佳位置：\(comparison.bestLocationName ?? "--")")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 14) {
                    ForEach(comparison.locations, id: \.name) { location in
                        HStack {
                            Text(location.name).font(.title3.bold())
                            Spacer()
                            Text("\(location.score) 分")
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(location.name == comparison.bestLocationName ? Color.cyan : .white)
                        }
                        .padding(18)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                }

                if let improvement = comparison.downloadImprovementPercent, improvement > 0 {
                    Text("活动下载速率 +\(Int(improvement.rounded()))%")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(Color.cyan)
                }

                Spacer()
                Text("本地测试 · 未包含主动公网测速")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(42)
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import AudioToolbox
import Combine
import F50Core
import Photos
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

private struct SignalChartPoint: Identifiable {
    let id = UUID()
    let score: Double
    let strength: Double?
    let interference: Double?
    let isStablePhase: Bool
}

private enum DeepInsightResultSort: String, CaseIterable, Identifiable {
    case score = "按分数"
    case time = "按时间"

    var id: Self { self }
}

@MainActor
private final class SignalLabSession: ObservableObject {
    @Published private(set) var insight: LiveSignalInsight
    @Published private(set) var locations: [LocationReport] = []
    @Published private(set) var isTesting = false
    @Published private(set) var isExtending = false
    @Published private(set) var progress = 0.0
    @Published private(set) var pendingReport: LocationReport?
    @Published var pendingLocationName = ""
    @Published private(set) var recentPoints: [SignalChartPoint] = []
    @Published private(set) var resultMessage: String?

    private let engine = NetworkInsightEngine()
    private let locationsDefaultsKey = "F50_iOS_SignalLabLocations_v1"
    private let placementPhotoDirectory = "F50SpotInsightPlacementPhotos"
    private let warmupDuration: TimeInterval = 5
    private let maximumExtension: TimeInterval = 60
    let duration: TimeInterval = 30
    let minimumValidSampleCount = 8
    private var locationSamples: [TelemetrySample] = []
    private var startedAt: Date?
    private var nextSoundAt = Date.distantPast
    private var activeDeviceIdentifier = ""

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
            recentPoints.append(SignalChartPoint(
                score: Double(insight.score.value),
                strength: insight.score.strengthScore.map(Double.init),
                interference: insight.score.interferenceScore.map(Double.init),
                isStablePhase: elapsed(at: now) >= warmupDuration
            ))
            if recentPoints.count > 60 { recentPoints.removeFirst(recentPoints.count - 60) }
            updateProgress(at: now)
        }
    }

    func configure(deviceIdentifier: String) {
        activeDeviceIdentifier = deviceIdentifier
    }

    func start(with status: F50Status, deviceIdentifier: String) {
        activeDeviceIdentifier = deviceIdentifier
        engine.reset()
        locationSamples.removeAll(keepingCapacity: true)
        recentPoints.removeAll(keepingCapacity: true)
        resultMessage = nil
        startedAt = Date()
        progress = 0
        isExtending = false
        nextSoundAt = .distantPast
        isTesting = true
        receive(status)
    }

    func tick(at now: Date = Date()) {
        guard isTesting else { return }
        updateProgress(at: now)
        guard elapsed(at: now) >= warmupDuration,
              now >= nextSoundAt,
              insight.score.confidence >= 0.5
        else { return }
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let scoreRatio = Double(insight.score.value) / 100
        nextSoundAt = now.addingTimeInterval(max(0.32, 1.35 - scoreRatio))
    }

    func finish() {
        guard isTesting else { return }
        isTesting = false
        isExtending = false
        progress = 1
        let stableSamples = validStableSamples
        if stableSamples.count >= minimumValidSampleCount {
            let observedDuration = max(1, elapsed(at: Date()) - warmupDuration)
            pendingReport = engine.makeLocationReport(
                name: "",
                samples: stableSamples,
                deviceIdentifier: activeDeviceIdentifier,
                durationSeconds: duration,
                observedDurationSeconds: observedDuration
            )
            pendingLocationName = ""
        } else {
            resultMessage = "有效样本仅 \(stableSamples.count)/\(minimumValidSampleCount)，本次结果未保存"
        }
        locationSamples.removeAll()
        startedAt = nil
    }

    func cancel() {
        guard isTesting else { return }
        isTesting = false
        isExtending = false
        progress = 0
        locationSamples.removeAll()
        startedAt = nil
        resultMessage = "已取消本次测试"
    }

    func savePendingResult(photo: UIImage?) -> String {
        let name = pendingLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let report = pendingReport, !name.isEmpty else { return "请输入位置名称" }

        let photoFilename: String?
        if let photo {
            guard let data = photo.jpegData(compressionQuality: 0.82) else { return "摆放位置照片无法处理" }
            let filename = "\(UUID().uuidString).jpg"
            do {
                try FileManager.default.createDirectory(at: placementPhotoDirectoryURL, withIntermediateDirectories: true)
                try data.write(to: placementPhotoDirectoryURL.appendingPathComponent(filename), options: .atomic)
                photoFilename = filename
            } catch {
                return "摆放位置照片未能写入"
            }
        } else {
            photoFilename = nil
        }

        let savedReport = LocationReport(
            name: name, sampleCount: report.sampleCount, score: report.score,
            averageLatencyMilliseconds: report.averageLatencyMilliseconds,
            averagePacketLossPercent: report.averagePacketLossPercent,
            averageDownloadBytesPerSecond: report.averageDownloadBytesPerSecond,
            averageUploadBytesPerSecond: report.averageUploadBytesPerSecond,
            fiveGOnlineRate: report.fiveGOnlineRate, switchCount: report.switchCount,
            testedAt: report.testedAt, deviceIdentifier: report.deviceIdentifier,
            networkType: report.networkType, band: report.band, pci: report.pci,
            durationSeconds: report.durationSeconds, observedDurationSeconds: report.observedDurationSeconds,
            validSampleCount: report.validSampleCount, scoreVersion: report.scoreVersion,
            stabilityScore: report.stabilityScore, averageRSRP: report.averageRSRP,
            averageSNR: report.averageSNR, averageRSRQ: report.averageRSRQ,
            switchRatePerMinute: report.switchRatePerMinute, placementPhotoFilename: photoFilename
        )
        let replacedReports = locations.filter {
            $0.name == savedReport.name
                && $0.isComparable(deviceIdentifier: activeDeviceIdentifier, durationSeconds: duration)
        }
        removePlacementPhotos(for: replacedReports)
        locations.removeAll { replacedReports.contains($0) }
        locations.append(savedReport)
        persistLocations()
        pendingReport = nil
        pendingLocationName = ""
        return photoFilename == nil ? "Deep Insight 结果已保存" : "Deep Insight 结果和摆放位置照片已保存"
    }

    func discardPendingResult() {
        pendingReport = nil
        pendingLocationName = ""
    }

    func removeLocations(_ reports: [LocationReport]) {
        removePlacementPhotos(for: reports)
        locations.removeAll { reports.contains($0) }
        persistLocations()
    }

    func placementPhoto(for report: LocationReport) -> UIImage? {
        guard let filename = report.placementPhotoFilename else { return nil }
        return UIImage(contentsOfFile: placementPhotoDirectoryURL.appendingPathComponent(filename).path)
    }

    func removeIncompatibleLocations(at offsets: IndexSet) {
        let sorted = incompatibleLocations
        let reports = offsets.compactMap { sorted.indices.contains($0) ? sorted[$0] : nil }
        removePlacementPhotos(for: reports)
        locations.removeAll { reports.contains($0) }
        persistLocations()
    }

    var comparableLocations: [LocationReport] {
        locations.filter { $0.isComparable(deviceIdentifier: activeDeviceIdentifier, durationSeconds: duration) }
    }

    var comparison: LocationComparison { engine.compareLocations(comparableLocations) }

    var incompatibleLocations: [LocationReport] {
        locations.filter { !comparableLocations.contains($0) }.sorted {
            ($0.testedAt ?? .distantPast) > ($1.testedAt ?? .distantPast)
        }
    }

    var validSampleCount: Int { validStableSamples.count }

    private var validStableSamples: [TelemetrySample] {
        guard let startedAt else { return [] }
        return locationSamples.filter {
            $0.timestamp.timeIntervalSince(startedAt) >= warmupDuration
                && $0.online
                && ($0.dataAgeSeconds ?? 0) <= 10
                && engine.signalScore(for: $0).confidence >= 0.5
        }
    }

    private func updateProgress(at now: Date) {
        guard let startedAt else { return }
        progress = min(1, max(0, now.timeIntervalSince(startedAt) / duration))
        let elapsed = now.timeIntervalSince(startedAt)
        isExtending = elapsed >= duration && validSampleCount < minimumValidSampleCount
        if elapsed >= duration, validSampleCount >= minimumValidSampleCount {
            finish()
        } else if elapsed >= duration + maximumExtension {
            finish()
        }
    }

    private func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    private func persistLocations() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        UserDefaults.standard.set(data, forKey: locationsDefaultsKey)
    }

    private var placementPhotoDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(placementPhotoDirectory, isDirectory: true)
    }

    private func removePlacementPhotos(for reports: [LocationReport]) {
        for filename in Set(reports.compactMap(\.placementPhotoFilename)) {
            try? FileManager.default.removeItem(at: placementPhotoDirectoryURL.appendingPathComponent(filename))
        }
    }
}

struct SignalLabView: View {
    @ObservedObject var fetcher: F50Fetcher
    @StateObject private var session = SignalLabSession()
    @State private var shareImage: UIImage?
    @State private var placementPhoto: UIImage?
    @State private var previewPlacementPhoto: UIImage?
    @State private var saveMessage: String?
    @State private var resultSort: DeepInsightResultSort = .score
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    VStack(spacing: 8) {
                        Text("实时评分")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(session.insight.score.value)")
                                .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(scoreColor)
                            Text("分")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)

                        }
                        .frame(width: 136)
                        ProgressView(value: Double(session.insight.score.value), total: 100)
                            .tint(scoreColor)
                            .frame(width: 136)
                    }
                    .padding(.bottom, 4)

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

                    VStack(spacing: 2) {
                        HStack(spacing: 8) {
                            Text(fetcher.status.networkType)
                            if !fetcher.status.currentBands.isEmpty {
                                Text(fetcher.status.currentBands)
                            }
                            if let pci = fetcher.status.pci {
                                Text("PCI \(pci)")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        Text(dataQualityText)
                            .font(.caption2)
                            .foregroundStyle(session.insight.score.isStale ? .orange : .secondary)
                    }
                    .padding(.top, 4)

                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                if session.isTesting {
                    VStack(spacing: 14) {
                        SignalTrendChart(points: session.recentPoints)
                            .frame(height: 112)
                        ProgressView(value: session.progress)
                        if session.isExtending {
                            Text("数据不足，正在延长采样")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("取消测试", role: .destructive) { session.cancel() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .frame(maxWidth: .infinity)
                    }
                    .listRowSeparator(.hidden)
                } else {
                    Button {
                        session.start(with: fetcher.status, deviceIdentifier: deviceIdentifier)
                    } label: {
                        Text("开始 Spot Deep Insight")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.insight.score.confidence < 0.5)
                }

                if let resultMessage = session.resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(resultMessage.contains("已保存") ? .green : .secondary)
                }
            } header: {
                Text("Spot Deep Insight")
            }

            if !session.comparableLocations.isEmpty {
                Section {
                    ForEach(displayedLocations, id: \.name) { location in
                        LocationResultRow(
                            location: location,
                            placementPhoto: session.placementPhoto(for: location),
                            rankMedal: rankMedal(for: location)
                        ) {
                            previewPlacementPhoto = $0
                        }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    session.removeLocations([location])
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .tint(.red)
                                .accessibilityLabel("删除")
                                Button {
                                    shareImage = SignalShareRenderer.render(
                                        location: location,
                                        placementPhoto: session.placementPhoto(for: location)
                                    )
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.caption)
                                }
                                .tint(.blue)
                                .accessibilityLabel("分享")
                            }
                    }
                    .onDelete { offsets in
                        session.removeLocations(offsets.compactMap { index in
                            displayedLocations.indices.contains(index) ? displayedLocations[index] : nil
                        })
                    }
                } header: {
                    HStack {
                        Text("Deep Insight 结果")
                        Spacer()
                        Menu {
                            Picker("排序", selection: $resultSort) {
                                ForEach(DeepInsightResultSort.allCases) { sort in
                                    Text(sort.rawValue).tag(sort)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("结果排序：\(resultSort.rawValue)")
                    }
                }
            }

            if !session.incompatibleLocations.isEmpty {
                Section {
                    ForEach(session.incompatibleLocations.indices, id: \.self) { index in
                        let location = session.incompatibleLocations[index]
                        LocationResultRow(location: location, placementPhoto: session.placementPhoto(for: location), rankMedal: nil) {
                            previewPlacementPhoto = $0
                        }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    session.removeIncompatibleLocations(at: IndexSet(integer: index))
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .tint(.red)
                                .accessibilityLabel("删除")
                                Button {
                                    shareImage = SignalShareRenderer.render(
                                        location: location,
                                        placementPhoto: session.placementPhoto(for: location)
                                    )
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.caption)
                                }
                                .tint(.blue)
                                .accessibilityLabel("分享")
                            }
                    }
                    .onDelete(perform: session.removeIncompatibleLocations)
                } header: {
                    Text("历史记录（不参与本组比较）")
                } footer: {
                    Text("旧算法、其他设备或不同时长的结果不会与当前测试混排。")
                }
            }

            Section("评分说明") {
                Text("评分依据最近采集的 RSRP、SINR/SNR 与 RSRQ；指标缺失或数据陈旧时会降低可信度。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spot Insight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            session.configure(deviceIdentifier: deviceIdentifier)
            session.receive(fetcher.status)
        }
        .onReceive(fetcher.$status) { session.receive($0) }
        .onReceive(clock) { session.tick(at: $0) }
        .fullScreenCover(isPresented: Binding(
            get: { shareImage != nil },
            set: { if !$0 { shareImage = nil } }
        )) {
            if let shareImage {
                SignalSharePreview(image: shareImage)
            }
        }
        .sheet(isPresented: Binding(
            get: { session.pendingReport != nil },
            set: {
                if !$0 {
                    session.discardPendingResult()
                    placementPhoto = nil
                }
            }
        )) {
            DeepInsightSaveSheet(
                locationName: $session.pendingLocationName,
                photo: $placementPhoto
            ) {
                saveMessage = session.savePendingResult(photo: placementPhoto)
                placementPhoto = nil
            }
        }
        .alert("Deep Insight", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
        .fullScreenCover(isPresented: Binding(
            get: { previewPlacementPhoto != nil },
            set: { if !$0 { previewPlacementPhoto = nil } }
        )) {
            if let previewPlacementPhoto {
                PlacementPhotoPreview(photo: previewPlacementPhoto)
            }
        }
    }

    private var deviceIdentifier: String {
        F50Configuration.displayAddress(from: fetcher.baseURLString)
    }

    private var displayedLocations: [LocationReport] {
        switch resultSort {
        case .score:
            return session.comparison.locations
        case .time:
            return session.comparableLocations.sorted {
                ($0.testedAt ?? .distantPast) > ($1.testedAt ?? .distantPast)
            }
        }
    }

    private func rankMedal(for location: LocationReport) -> String? {
        guard let index = session.comparison.locations.firstIndex(of: location) else { return nil }
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return nil
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
            ProgressView(value: Double(value ?? 0), total: 100)
                .tint(scoreIndicatorColor(value))
                .frame(width: 42)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func scoreIndicatorColor(_ value: Int?) -> Color {
        switch value ?? 0 {
        case 80...: return .green
        case 60...: return .blue
        case 40...: return .orange
        default: return .red
        }
    }

    private var dataQualityText: String {
        let confidence = Int((session.insight.score.confidence * 100).rounded())
        let sources = Int((session.insight.score.sourceCoverage * 100).rounded())
        return "可信度 \(confidence)% · 来源完整度 \(sources)%"
    }
}

private struct SignalTrendChart: View {
    let points: [SignalChartPoint]

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack {
                    ForEach([0.25, 0.5, 0.75], id: \.self) { ratio in
                        Path { path in
                            let y = geometry.size.height * ratio
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    }

                    if let stableIndex = points.firstIndex(where: \.isStablePhase), stableIndex > 0 {
                        Path { path in
                            let x = xPosition(for: stableIndex, width: geometry.size.width)
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }
                        .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }

                    metricPath(points.map { Optional($0.score) }, size: geometry.size)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                    metricPath(points.map(\.strength), size: geometry.size)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    metricPath(points.map(\.interference), size: geometry.size)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }

            HStack(spacing: 12) {
                legend("综合", color: .blue)
                legend("强度", color: .green)
                legend("干扰", color: .orange)
                Spacer()
                Text("虚线后为稳定采样")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("信号趋势图，共 \(points.count) 个采样")
    }

    private func metricPath(_ values: [Double?], size: CGSize) -> Path {
        Path { path in
            var hasPoint = false
            for (index, value) in values.enumerated() {
                guard let value else {
                    hasPoint = false
                    continue
                }
                let point = CGPoint(
                    x: xPosition(for: index, width: size.width),
                    y: size.height * (1 - min(100, max(0, value)) / 100)
                )
                if hasPoint { path.addLine(to: point) } else { path.move(to: point) }
                hasPoint = true
            }
        }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        guard points.count > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(points.count - 1)
    }

    private func legend(_ title: String, color: Color) -> some View {
        Label {
            Text(title).font(.caption2)
        } icon: {
            Circle().fill(color).frame(width: 6, height: 6)
        }
        .foregroundStyle(.secondary)
    }
}

private struct LocationResultRow: View {
    let location: LocationReport
    let placementPhoto: UIImage?
    let rankMedal: String?
    let onPhotoTap: (UIImage) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(location.name).font(.headline)
                    if let rankMedal {
                        Text(rankMedal)
                            .accessibilityLabel("第 \(rankMedal == "🥇" ? 1 : rankMedal == "🥈" ? 2 : 3) 名")
                    }
                    Spacer()
                    Text("\(location.score) 分")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(scoreColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(scoreColor.opacity(0.12), in: Capsule())
                }
                if let testedAt = location.testedAt {
                    Text(testedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(networkIdentity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    signalMetric("RSRP", value: location.averageRSRP, thresholds: [-85, -95, -105])
                    signalMetric("SINR", value: location.averageSNR, thresholds: [20, 13, 3])
                    signalMetric("RSRQ", value: location.averageRSRQ, thresholds: [-10, -15, -20])
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let placementPhoto {
                Button { onPhotoTap(placementPhoto) } label: {
                    Image(uiImage: placementPhoto)
                        .resizable()
                        .scaledToFit()
                        .frame(width: thumbnailWidth(for: placementPhoto), height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看摆放位置照片")
                .layoutPriority(1)
            } else {
                Color.clear
                    .frame(width: 64, height: 64)
                    .layoutPriority(1)
            }
        }
    }

    private var networkIdentity: String {
        let values = [location.networkType, location.band, location.pci.map { "PCI \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return values.isEmpty ? "网络信息不可用" : values.joined(separator: " ・ ")
    }

    private var scoreColor: Color {
        switch location.score {
        case 80...: return .green
        case 60...: return .blue
        case 40...: return .orange
        default: return .red
        }
    }

    private func thumbnailWidth(for photo: UIImage) -> CGFloat {
        guard photo.size.height > 0 else { return 64 }
        return 64 * photo.size.width / photo.size.height
    }

    private func signalMetric(_ title: String, value: Double?, thresholds: [Double]) -> some View {
        let quality = signalQuality(value, thresholds: thresholds)
        return HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 2)
                .fill(quality.color)
                .frame(width: CGFloat(24 * quality.ratio), height: 3)
                .frame(width: 24, alignment: .leading)
            Text(value.map { String(format: "%.0f", $0) } ?? "--")
                .foregroundStyle(quality.color)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption2.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signalQuality(_ value: Double?, thresholds: [Double]) -> (color: Color, ratio: Double) {
        guard let value else { return (.secondary, 0) }
        if value >= thresholds[0] { return (.green, 1) }
        if value >= thresholds[1] { return (.blue, 0.75) }
        if value >= thresholds[2] { return (.orange, 0.5) }
        return (.red, 0.25)
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
        .onReceive(clock) { now in
            session.tick(at: now)
            Task { await session.probeConnectivity(with: fetcher.status, at: now) }
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
    static func render(location: LocationReport, placementPhoto: UIImage?) -> UIImage? {
        let width: CGFloat = 540
        let photoHeight = placementPhoto.map { image in
            min(900, max(600, width * image.size.height / image.size.width))
        } ?? 720
        let renderer = ImageRenderer(
            content: SignalShareCard(location: location, placementPhoto: placementPhoto, panelHeight: photoHeight * 0.2)
                .frame(width: width, height: photoHeight)
        )
        renderer.scale = 2
        return renderer.uiImage
    }
}

private struct SignalShareCard: View {
    let location: LocationReport
    let placementPhoto: UIImage?
    let panelHeight: CGFloat

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.075)
            if let placementPhoto {
                Image(uiImage: placementPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            LinearGradient(
                colors: [.black.opacity(0.44), .clear, .black.opacity(0.66)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("F50 MONITOR")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("SPOT DEEP INSIGHT")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.cyan)
                    Text(location.name)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(testedAtText)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(networkIdentity)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                HStack(alignment: .bottom, spacing: 16) {
                    scoreModule
                    GeometryReader { proxy in
                        let columnWidth = proxy.size.width / 3
                        ZStack {
                            HStack(spacing: 0) {
                                shareMetric("RSRP", location.averageRSRP, thresholds: [-85, -95, -105])
                                    .frame(width: columnWidth)
                                shareMetric("SINR", location.averageSNR, thresholds: [20, 13, 3])
                                    .frame(width: columnWidth)
                                shareMetric("RSRQ", location.averageRSRQ, thresholds: [-10, -15, -20])
                                    .frame(width: columnWidth)
                            }
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 1, height: 58)
                                .position(x: columnWidth, y: proxy.size.height / 2)
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 1, height: 58)
                                .position(x: columnWidth * 2, y: proxy.size.height / 2)
                        }
                    }
                    .frame(height: 62)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(height: panelHeight)
                .background {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.black.opacity(0.14))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(.white.opacity(0.28), lineWidth: 1)
                        }
                }
            }
            .padding(28)
        }
        .environment(\.colorScheme, .dark)
    }

    private var scoreModule: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("综合评分")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
            Text("\(location.score)")
                .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(scoreColor)
            shareIndicator(value: Double(location.score) / 100, color: scoreColor)
        }
        .frame(width: 145, alignment: .leading)
    }

    private var testedAtText: String {
        location.testedAt?.formatted(date: .abbreviated, time: .shortened) ?? ""
    }

    private var networkIdentity: String {
        [location.networkType, location.band, location.pci.map { "PCI \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ・ ")
    }

    private var scoreColor: Color {
        switch location.score {
        case 80...: return .green
        case 60...: return .blue
        case 40...: return .orange
        default: return .red
        }
    }

    private func shareMetric(_ title: String, _ value: Double?, thresholds: [Double]) -> some View {
        let quality = signalQuality(value, thresholds: thresholds)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(value.map { String(format: "%.0f", $0) } ?? "--")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            shareIndicator(value: quality.ratio, color: quality.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private func shareIndicator(value: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 5)
    }

    private func signalQuality(_ value: Double?, thresholds: [Double]) -> (color: Color, ratio: Double) {
        guard let value else { return (.secondary, 0) }
        if value >= thresholds[0] { return (.green, 1) }
        if value >= thresholds[1] { return (.blue, 0.75) }
        if value >= thresholds[2] { return (.orange, 0.5) }
        return (.red, 0.25)
    }
}

private struct PlacementPhotoPreview: View {
    let photo: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .padding()
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            if value.translation.height > 120 {
                                dismiss()
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                            }
                        }
                )
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding()
            }
            .accessibilityLabel("关闭照片预览")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

private struct SignalSharePreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false
    @State private var saveMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .padding(.bottom, 110)
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("关闭分享预览")
                }
                .padding()
                Spacer()
                HStack(spacing: 12) {
                    Button { saveToPhotoLibrary() } label: {
                        Label("保存", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button { isSharing = true } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $isSharing) {
            ActivityViewController(items: [image])
        }
        .alert("保存分享图", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
    }

    private func saveToPhotoLibrary() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { saveMessage = "未获照片图库写入权限" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    saveMessage = success ? "已保存到照片图库" : "保存失败，请稍后重试"
                }
            }
        }
    }
}

private struct DeepInsightSaveSheet: View {
    @Binding var locationName: String
    @Binding var photo: UIImage?
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCameraPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("位置名称") {
                    TextField("例如：书桌右侧", text: $locationName)
                        .textInputAutocapitalization(.never)
                }

                Section("摆放位置照片（可选）") {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button(photo == nil ? "拍摄摆放位置" : "重新拍摄") {
                        isCameraPresented = true
                    }
                }
            }
            .navigationTitle("保存 Deep Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            PlacementCameraPicker { image in
                if let image { photo = image }
                isCameraPresented = false
            }
            .ignoresSafeArea()
        }
    }
}

private struct PlacementCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

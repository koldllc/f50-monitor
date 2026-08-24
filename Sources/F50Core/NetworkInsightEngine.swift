import Foundation

/// One normalized modem observation.  The engine does not infer a missing
/// radio metric; nil values are retained and reduce the confidence of a score.
public struct TelemetrySample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let online: Bool
    public let networkType: String
    public let rsrp: Double?
    public let rsrq: Double?
    public let snr: Double?
    public let band: String?
    public let temperature: Double?
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public let latencyMilliseconds: Double?
    public let packetLossPercent: Double?
    public let pci: String?
    public let cellId: String?
    public let tac: String?
    public let rsrpSource: String?
    public let rsrqSource: String?
    public let snrSource: String?
    public let snrKind: SignalNoiseMetricKind
    public let dataAgeSeconds: Double?

    public init(
        timestamp: Date = Date(),
        online: Bool,
        networkType: String,
        rsrp: Double? = nil,
        rsrq: Double? = nil,
        snr: Double? = nil,
        band: String? = nil,
        temperature: Double? = nil,
        downloadBytesPerSecond: Double = 0,
        uploadBytesPerSecond: Double = 0,
        latencyMilliseconds: Double? = nil,
        packetLossPercent: Double? = nil,
        pci: String? = nil,
        cellId: String? = nil,
        tac: String? = nil,
        rsrpSource: String? = nil,
        rsrqSource: String? = nil,
        snrSource: String? = nil,
        snrKind: SignalNoiseMetricKind = .unknown,
        dataAgeSeconds: Double? = nil
    ) {
        self.timestamp = timestamp
        self.online = online
        self.networkType = networkType
        self.rsrp = rsrp
        self.rsrq = rsrq
        self.snr = snr
        self.band = band
        self.temperature = temperature
        self.downloadBytesPerSecond = max(0, downloadBytesPerSecond)
        self.uploadBytesPerSecond = max(0, uploadBytesPerSecond)
        self.latencyMilliseconds = latencyMilliseconds.map { max(0, $0) }
        self.packetLossPercent = packetLossPercent.map { min(100, max(0, $0)) }
        self.pci = pci
        self.cellId = cellId
        self.tac = tac
        self.rsrpSource = rsrpSource
        self.rsrqSource = rsrqSource
        self.snrSource = snrSource
        self.snrKind = snrKind
        self.dataAgeSeconds = dataAgeSeconds.map { max(0, $0) }
    }

    public var is5G: Bool {
        let value = networkType.lowercased()
        return value.contains("5g") || value.contains("nr")
    }
}

public enum SignalTrend: String, Codable, Equatable, Sendable {
    case up
    case down
    case stable
    case insufficient
}

public struct SignalScore: Codable, Equatable, Sendable {
    public let value: Int
    public let confidence: Double
    public let rsrpComponent: Double?
    public let snrComponent: Double?
    public let rsrqComponent: Double?
    public let sourceCoverage: Double
    public let isStale: Bool

    public init(value: Int, confidence: Double, rsrpComponent: Double?, snrComponent: Double?, rsrqComponent: Double?, sourceCoverage: Double = 0, isStale: Bool = false) {
        self.value = min(100, max(0, value))
        self.confidence = min(1, max(0, confidence))
        self.rsrpComponent = rsrpComponent
        self.snrComponent = snrComponent
        self.rsrqComponent = rsrqComponent
        self.sourceCoverage = min(1, max(0, sourceCoverage))
        self.isStale = isStale
    }

    /// Alias for callers that present the value as “信号评分”.
    public var score: Int { value }

    public var strengthScore: Int? { rsrpComponent.map { Int($0.rounded()) } }

    public var interferenceScore: Int? {
        let values = [(snrComponent, 2.0), (rsrqComponent, 1.0)].compactMap { item in
            item.0.map { ($0, item.1) }
        }
        guard !values.isEmpty else { return nil }
        let totalWeight = values.reduce(0) { $0 + $1.1 }
        return Int((values.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight).rounded())
    }
}

public struct LiveSignalInsight: Codable, Equatable, Sendable {
    public let score: SignalScore
    public let trend: SignalTrend
    public let fiveGOnlineRate: Double
    public let recommendation: String
    public let sampleCount: Int
    public let stabilityScore: Int
    public let noiseMetricKind: SignalNoiseMetricKind

    public init(score: SignalScore, trend: SignalTrend, fiveGOnlineRate: Double, recommendation: String, sampleCount: Int, stabilityScore: Int, noiseMetricKind: SignalNoiseMetricKind) {
        self.score = score
        self.trend = trend
        self.fiveGOnlineRate = fiveGOnlineRate
        self.recommendation = recommendation
        self.sampleCount = sampleCount
        self.stabilityScore = min(100, max(0, stabilityScore))
        self.noiseMetricKind = noiseMetricKind
    }
}

public struct NetworkSwitchEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let from: String
    public let to: String

    public init(timestamp: Date, from: String, to: String) {
        self.timestamp = timestamp
        self.from = from
        self.to = to
    }
}

public struct NetworkSwitchSummary: Codable, Equatable, Sendable {
    public let total: Int
    public let fiveGToLTE: Int
    public let lteToFiveG: Int
    public let other: Int
    public let events: [NetworkSwitchEvent]

    public init(total: Int, fiveGToLTE: Int, lteToFiveG: Int, other: Int, events: [NetworkSwitchEvent]) {
        self.total = total
        self.fiveGToLTE = fiveGToLTE
        self.lteToFiveG = lteToFiveG
        self.other = other
        self.events = events
    }
}

public enum CellularChangeKind: String, Codable, Equatable, Sendable {
    case band
    case pci
    case cellId
    case tac
}

public struct CellularChangeEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let kind: CellularChangeKind
    public let from: String
    public let to: String

    public init(timestamp: Date, kind: CellularChangeKind, from: String, to: String) {
        self.timestamp = timestamp
        self.kind = kind
        self.from = from
        self.to = to
    }
}

public struct LocationReport: Codable, Equatable, Sendable {
    public let name: String
    public let sampleCount: Int
    public let score: Int
    public let averageLatencyMilliseconds: Double?
    public let averagePacketLossPercent: Double?
    public let averageDownloadBytesPerSecond: Double
    public let averageUploadBytesPerSecond: Double
    public let fiveGOnlineRate: Double
    public let switchCount: Int

    public init(name: String, sampleCount: Int, score: Int, averageLatencyMilliseconds: Double?, averagePacketLossPercent: Double?, averageDownloadBytesPerSecond: Double, averageUploadBytesPerSecond: Double, fiveGOnlineRate: Double, switchCount: Int) {
        self.name = name
        self.sampleCount = sampleCount
        self.score = min(100, max(0, score))
        self.averageLatencyMilliseconds = averageLatencyMilliseconds
        self.averagePacketLossPercent = averagePacketLossPercent
        self.averageDownloadBytesPerSecond = averageDownloadBytesPerSecond
        self.averageUploadBytesPerSecond = averageUploadBytesPerSecond
        self.fiveGOnlineRate = fiveGOnlineRate
        self.switchCount = switchCount
    }
}

public struct LocationComparison: Codable, Equatable, Sendable {
    public let locations: [LocationReport]
    public let bestLocationName: String?
    public let downloadImprovementPercent: Double?

    public init(locations: [LocationReport], bestLocationName: String?, downloadImprovementPercent: Double?) {
        self.locations = locations
        self.bestLocationName = bestLocationName
        self.downloadImprovementPercent = downloadImprovementPercent
    }
}

public enum DoctorFindingCategory: String, Codable, CaseIterable, Sendable {
    case insufficientData
    case coverage
    case interference
    case frequentSwitching
    case possibleOverheating
    case networkQuality
}

public struct DoctorFinding: Codable, Equatable, Sendable {
    public let category: DoctorFindingCategory
    public let title: String
    public let summary: String
    public let evidence: [String]
    public let confidence: Double

    public init(category: DoctorFindingCategory, title: String, summary: String, evidence: [String], confidence: Double) {
        self.category = category
        self.title = title
        self.summary = summary
        self.evidence = evidence
        self.confidence = min(1, max(0, confidence))
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public let start: Date?
    public let end: Date?
    public let sampleCount: Int
    public let fiveGOnlineRate: Double
    public let switchSummary: NetworkSwitchSummary
    public let findings: [DoctorFinding]
    // 可选以兼容第一阶段已保存的本地报告。
    public let cellularChanges: [CellularChangeEvent]?

    public init(start: Date?, end: Date?, sampleCount: Int, fiveGOnlineRate: Double, switchSummary: NetworkSwitchSummary, findings: [DoctorFinding], cellularChanges: [CellularChangeEvent]? = nil) {
        self.start = start
        self.end = end
        self.sampleCount = sampleCount
        self.fiveGOnlineRate = fiveGOnlineRate
        self.switchSummary = switchSummary
        self.findings = findings
        self.cellularChanges = cellularChanges
    }

    public var primaryFinding: DoctorFinding? { findings.first }
}

/// Pure local analysis for Signal Lab and Network Doctor.
///
/// The interface is intentionally small: append normalized observations and
/// read a report.  It performs no persistence, network probes, UI, or sound.
public final class NetworkInsightEngine: @unchecked Sendable {
    public private(set) var samples: [TelemetrySample]

    public init(samples: [TelemetrySample] = []) {
        self.samples = samples.sorted { $0.timestamp < $1.timestamp }
    }

    @discardableResult
    public func append(_ sample: TelemetrySample) -> LiveSignalInsight {
        samples.append(sample)
        samples.sort { $0.timestamp < $1.timestamp }
        return liveInsight
    }

    public func reset() { samples.removeAll(keepingCapacity: true) }

    public var liveInsight: LiveSignalInsight {
        let score = signalScore(for: smoothedSample(from: samples))
        let currentTrend = trend(for: samples)
        let stability = stabilityScore(in: samples)
        let recommendationText: String
        if samples.last?.online == false {
            recommendationText = "设备当前未在线，请先检查连接"
        } else if score.isStale {
            recommendationText = "数据已陈旧，请等待设备刷新"
        } else {
            recommendationText = recommendation(for: score, trend: currentTrend)
        }
        return LiveSignalInsight(
            score: score,
            trend: currentTrend,
            fiveGOnlineRate: fiveGRate(in: samples),
            recommendation: recommendationText,
            sampleCount: samples.count,
            stabilityScore: stability,
            noiseMetricKind: samples.last?.snrKind ?? .unknown
        )
    }

    public func signalScore(for sample: TelemetrySample?) -> SignalScore {
        guard let sample else { return SignalScore(value: 0, confidence: 0, rsrpComponent: nil, snrComponent: nil, rsrqComponent: nil) }
        let components: [(Double?, Double)] = [
            (sample.rsrp.map { linear($0, low: -120, high: -80) }, 40),
            (sample.snr.map { linear($0, low: -5, high: 30) }, 40),
            (sample.rsrq.map { linear($0, low: -20, high: -3) }, 20)
        ]
        let available = components.compactMap { item -> (Double, Double)? in
            guard let value = item.0, value.isFinite else { return nil }
            return (value, item.1)
        }
        guard !available.isEmpty else {
            return SignalScore(value: 0, confidence: 0, rsrpComponent: nil, snrComponent: nil, rsrqComponent: nil)
        }
        let totalWeight = available.reduce(0) { $0 + $1.1 }
        let value = available.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
        let availableSources = [
            sample.rsrp == nil ? nil : sample.rsrpSource,
            sample.snr == nil ? nil : sample.snrSource,
            sample.rsrq == nil ? nil : sample.rsrqSource
        ]
        let sourceCoverage = Double(availableSources.compactMap { $0 }.count) / Double(available.count)
        let age = sample.dataAgeSeconds ?? 0
        let freshnessFactor = age <= 10 ? 1.0 : (age <= 30 ? 0.5 : 0.2)
        return SignalScore(
            value: Int(value.rounded()),
            confidence: totalWeight / 100 * freshnessFactor,
            rsrpComponent: components[0].0,
            snrComponent: components[1].0,
            rsrqComponent: components[2].0,
            sourceCoverage: sourceCoverage,
            isStale: age > 10
        )
    }

    public func makeLocationReport(name: String, samples: [TelemetrySample]) -> LocationReport {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        let onlineSamples = ordered.filter { $0.online && ($0.dataAgeSeconds ?? 0) <= 10 }
        let scores = onlineSamples.map { signalScore(for: $0) }
        let avgScore = weightedAverage(scores.map { Double($0.value) }) ?? 0
        let latency = average(ordered.compactMap(\.latencyMilliseconds))
        let loss = average(ordered.compactMap(\.packetLossPercent))
        let fiveGRate = fiveGRate(in: ordered)
        let switches = switchSummary(in: ordered).total + cellularChangeEvents(in: ordered).count
        let stabilityScore = max(0, 100 - Double(switches) * 25)
        let compositeScore = avgScore * 0.7 + fiveGRate * 100 * 0.2 + stabilityScore * 0.1
        return LocationReport(
            name: name,
            sampleCount: ordered.count,
            score: Int(compositeScore.rounded()),
            averageLatencyMilliseconds: latency,
            averagePacketLossPercent: loss,
            averageDownloadBytesPerSecond: average(ordered.map(\.downloadBytesPerSecond)) ?? 0,
            averageUploadBytesPerSecond: average(ordered.map(\.uploadBytesPerSecond)) ?? 0,
            fiveGOnlineRate: fiveGRate,
            switchCount: switches
        )
    }

    public func compareLocations(_ reports: [LocationReport]) -> LocationComparison {
        let sorted = reports.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.averageDownloadBytesPerSecond > $1.averageDownloadBytesPerSecond
        }
        guard let best = sorted.first else { return LocationComparison(locations: [], bestLocationName: nil, downloadImprovementPercent: nil) }
        let baseline = sorted.dropFirst().map(\.averageDownloadBytesPerSecond).max() ?? 0
        let improvement: Double?
        if baseline > 0 { improvement = (best.averageDownloadBytesPerSecond - baseline) / baseline * 100 } else { improvement = nil }
        return LocationComparison(locations: sorted, bestLocationName: best.name, downloadImprovementPercent: improvement)
    }

    public func diagnose(window: DateInterval? = nil) -> DoctorReport {
        let selected: [TelemetrySample]
        if let window {
            selected = samples.filter { window.contains($0.timestamp) }
        } else if let end = samples.last?.timestamp {
            selected = samples.filter { $0.timestamp >= end.addingTimeInterval(-600) }
        } else {
            selected = []
        }
        let freshSamples = selected.filter { ($0.dataAgeSeconds ?? 0) <= 10 }
        let summary = switchSummary(in: freshSamples)
        let cellChanges = cellularChangeEvents(in: freshSamples)
        var findings: [DoctorFinding] = []
        guard !selected.isEmpty else {
            findings.append(DoctorFinding(category: .insufficientData, title: "数据不足", summary: "还没有可用于分析的网络采样。", evidence: [], confidence: 0))
            return DoctorReport(start: nil, end: nil, sampleCount: 0, fiveGOnlineRate: 0, switchSummary: summary, findings: findings)
        }

        guard !freshSamples.isEmpty else {
            findings.append(DoctorFinding(category: .insufficientData, title: "数据已陈旧", summary: "现有采样已经过期，暂时不能可靠判断网络原因。", evidence: ["请保持工具页在前台等待新数据"], confidence: 0))
            return DoctorReport(start: selected.first?.timestamp, end: selected.last?.timestamp, sampleCount: selected.count, fiveGOnlineRate: 0, switchSummary: summary, findings: findings, cellularChanges: cellChanges)
        }

        let rsrp = freshSamples.compactMap(\.rsrp)
        let snr = freshSamples.compactMap(\.snr)
        let avgRSRP = average(rsrp)
        let snrDeviation = standardDeviation(snr)
        if let avgRSRP, avgRSRP < -105 {
            let confidence = min(0.95, 0.55 + Double(rsrp.filter { $0 < -105 }.count) / Double(max(1, rsrp.count)) * 0.4)
            findings.append(DoctorFinding(category: .coverage, title: "覆盖可能不足", summary: "信号强度持续偏低，更可能是覆盖或摆放位置问题。", evidence: ["平均 RSRP：\(format(avgRSRP)) dBm"], confidence: confidence))
        }
        if let avgRSRP, let snrDeviation, rsrp.count >= 2, snrDeviation >= 5 {
            let stableRSRP = (standardDeviation(rsrp) ?? 100) < 5
            if stableRSRP {
                findings.append(DoctorFinding(category: .interference, title: "可能存在无线干扰", summary: "RSRP 相对稳定，但 SINR/SNR 波动较大，更可能是无线干扰。", evidence: ["平均 RSRP：\(format(avgRSRP)) dBm", "SINR/SNR 波动：\(format(snrDeviation)) dB"], confidence: min(0.9, 0.55 + snrDeviation / 20)))
            }
        }
        let totalChanges = summary.total + cellChanges.count
        if totalChanges >= 3 {
            let bandChanges = cellChanges.filter { $0.kind == .band }.count
            let identityChanges = cellChanges.filter { $0.kind == .pci || $0.kind == .cellId }.count
            findings.append(DoctorFinding(category: .frequentSwitching, title: "小区或制式切换频繁", summary: "最近采样期间发生多次可确认切换，可能造成短时不稳定。", evidence: ["制式切换：\(summary.total) 次", "频段切换：\(bandChanges) 次", "小区标识切换：\(identityChanges) 次", "5G → LTE：\(summary.fiveGToLTE) 次", "LTE → 5G：\(summary.lteToFiveG) 次"], confidence: min(0.95, 0.5 + Double(totalChanges) / 20)))
        }
        let temperatures = freshSamples.compactMap(\.temperature)
        if let maxTemperature = temperatures.max(), maxTemperature >= 65 {
            findings.append(DoctorFinding(category: .possibleOverheating, title: "可能过热", summary: "设备温度偏高，可能与性能下降同时出现；仅凭采样不能证明因果关系。", evidence: ["最高温度：\(format(maxTemperature)) ℃"], confidence: min(0.95, 0.55 + (maxTemperature - 65) / 40)))
        }
        if let avgRSRP, avgRSRP >= -100 {
            let latency = average(freshSamples.compactMap(\.latencyMilliseconds))
            let loss = average(freshSamples.compactMap(\.packetLossPercent))
            if (latency ?? 0) >= 120 || (loss ?? 0) >= 5 {
                var evidence = ["平均 RSRP：\(format(avgRSRP)) dBm"]
                if let latency { evidence.append("平均延迟：\(format(latency)) ms") }
                if let loss { evidence.append("平均丢包：\(format(loss))%") }
                findings.append(DoctorFinding(category: .networkQuality, title: "无线信号尚可但网络质量较差", summary: "无线指标不差，但延迟或丢包偏高，更可能是拥塞、回程或上层网络问题。", evidence: evidence, confidence: 0.65))
            }
        }
        return makeDoctorReport(selected: freshSamples, summary: summary, findings: findings, cellularChanges: cellChanges)
    }

    private func makeDoctorReport(selected: [TelemetrySample], summary: NetworkSwitchSummary, findings: [DoctorFinding], cellularChanges: [CellularChangeEvent]) -> DoctorReport {
        let sortedFindings = findings.sorted { $0.confidence > $1.confidence }
        let dates = selected.map(\.timestamp)
        return DoctorReport(start: dates.min(), end: dates.max(), sampleCount: selected.count, fiveGOnlineRate: fiveGRate(in: selected), switchSummary: summary, findings: sortedFindings, cellularChanges: cellularChanges)
    }

    private func trend(for values: [TelemetrySample]) -> SignalTrend {
        let window = Array(values.suffix(12))
        guard window.count >= 4 else { return .insufficient }
        let half = window.count / 2
        let old = window.prefix(half).map { Double(signalScore(for: $0).value) }
        let recent = window.suffix(half).map { Double(signalScore(for: $0).value) }
        guard let oldAverage = average(old), let recentAverage = average(recent) else { return .insufficient }
        let delta = recentAverage - oldAverage
        if delta >= 2 { return .up }
        if delta <= -2 { return .down }
        return .stable
    }

    private func recommendation(for score: SignalScore, trend: SignalTrend) -> String {
        if score.confidence == 0 { return "等待更多信号数据" }
        if trend == .up { return "当前位置正在改善，保持观察" }
        if trend == .down { return "建议继续移动设备，寻找更稳定的位置" }
        if score.value < 45 { return "建议靠近窗边或移动设备" }
        return "当前位置稳定，可继续测试"
    }

    private func fiveGRate(in values: [TelemetrySample]) -> Double {
        let online = values.filter(\.online)
        guard !online.isEmpty else { return 0 }
        return Double(online.filter(\.is5G).count) / Double(online.count)
    }

    private func stabilityScore(in values: [TelemetrySample]) -> Int {
        let window = Array(values.suffix(12)).filter { ($0.dataAgeSeconds ?? 0) <= 10 }
        guard window.count >= 4 else { return 0 }
        let scores = window.map { Double(signalScore(for: $0).value) }
        let deviationPenalty = min(55, (standardDeviation(scores) ?? 0) * 5)
        let changeCount = switchSummary(in: window).total + cellularChangeEvents(in: window).count
        let changePenalty = min(45, Double(changeCount) * 15)
        return Int(max(0, 100 - deviationPenalty - changePenalty).rounded())
    }

    private func cellularChangeEvents(in values: [TelemetrySample]) -> [CellularChangeEvent] {
        let ordered = values.sorted { $0.timestamp < $1.timestamp }.filter(\.online)
        return (
            confirmedChangeEvents(kind: .band, samples: ordered, value: { $0.band })
            + confirmedChangeEvents(kind: .pci, samples: ordered, value: { $0.pci })
            + confirmedChangeEvents(kind: .cellId, samples: ordered, value: { $0.cellId })
            + confirmedChangeEvents(kind: .tac, samples: ordered, value: { $0.tac })
        ).sorted { $0.timestamp < $1.timestamp }
    }

    private func confirmedChangeEvents(
        kind: CellularChangeKind,
        samples: [TelemetrySample],
        value: (TelemetrySample) -> String?
    ) -> [CellularChangeEvent] {
        var confirmed: String?
        var candidate: String?
        var candidateStartedAt: Date?
        var candidateCount = 0
        var events: [CellularChangeEvent] = []

        for sample in samples {
            guard let current = value(sample)?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty else {
                candidate = nil
                candidateStartedAt = nil
                candidateCount = 0
                continue
            }
            guard let confirmedValue = confirmed else {
                confirmed = current
                continue
            }
            if current == confirmedValue {
                candidate = nil
                candidateStartedAt = nil
                candidateCount = 0
                continue
            }
            if candidate == current {
                candidateCount += 1
            } else {
                candidate = current
                candidateStartedAt = sample.timestamp
                candidateCount = 1
            }
            guard candidateCount >= 3 else { continue }
            events.append(CellularChangeEvent(
                timestamp: candidateStartedAt ?? sample.timestamp,
                kind: kind,
                from: confirmedValue,
                to: current
            ))
            confirmed = current
            candidate = nil
            candidateStartedAt = nil
            candidateCount = 0
        }
        return events
    }

    private func switchSummary(in values: [TelemetrySample]) -> NetworkSwitchSummary {
        let ordered = values.sorted(by: { $0.timestamp < $1.timestamp }).filter { $0.online && !$0.networkType.isEmpty }
        guard let first = ordered.first else {
            return NetworkSwitchSummary(total: 0, fiveGToLTE: 0, lteToFiveG: 0, other: 0, events: [])
        }

        var confirmed = first
        var candidateType: String?
        var candidateStartedAt: Date?
        var candidateCount = 0
        var events: [NetworkSwitchEvent] = []
        var fiveGToLTE = 0
        var lteToFiveG = 0

        for sample in ordered.dropFirst() {
            if sample.networkType == confirmed.networkType {
                candidateType = nil
                candidateStartedAt = nil
                candidateCount = 0
                continue
            }

            if candidateType == sample.networkType {
                candidateCount += 1
            } else {
                candidateType = sample.networkType
                candidateStartedAt = sample.timestamp
                candidateCount = 1
            }

            guard candidateCount >= 3 else { continue }
            let event = NetworkSwitchEvent(
                timestamp: candidateStartedAt ?? sample.timestamp,
                from: confirmed.networkType,
                to: sample.networkType
            )
            events.append(event)
            if confirmed.is5G && !sample.is5G { fiveGToLTE += 1 }
            else if !confirmed.is5G && sample.is5G { lteToFiveG += 1 }
            confirmed = sample
            candidateType = nil
            candidateStartedAt = nil
            candidateCount = 0
        }

        return NetworkSwitchSummary(total: events.count, fiveGToLTE: fiveGToLTE, lteToFiveG: lteToFiveG, other: events.count - fiveGToLTE - lteToFiveG, events: events)
    }

    private func smoothedSample(from values: [TelemetrySample]) -> TelemetrySample? {
        guard let latest = values.last else { return nil }
        let window = Array(values.suffix(5))
        return TelemetrySample(
            timestamp: latest.timestamp,
            online: latest.online,
            networkType: latest.networkType,
            rsrp: median(window.compactMap(\.rsrp)),
            rsrq: median(window.compactMap(\.rsrq)),
            snr: median(window.compactMap(\.snr)),
            band: latest.band,
            temperature: latest.temperature,
            downloadBytesPerSecond: latest.downloadBytesPerSecond,
            uploadBytesPerSecond: latest.uploadBytesPerSecond,
            latencyMilliseconds: latest.latencyMilliseconds,
            packetLossPercent: latest.packetLossPercent,
            pci: latest.pci,
            cellId: latest.cellId,
            tac: latest.tac,
            rsrpSource: latest.rsrpSource,
            rsrqSource: latest.rsrqSource,
            snrSource: latest.snrSource,
            snrKind: latest.snrKind,
            dataAgeSeconds: latest.dataAgeSeconds
        )
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func linear(_ value: Double, low: Double, high: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, (value - low) / (high - low) * 100))
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func weightedAverage(_ values: [Double]) -> Double? { average(values) }

    private func standardDeviation(_ values: [Double]) -> Double? {
        guard let mean = average(values), values.count >= 2 else { return nil }
        return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))
    }

    private func format(_ value: Double) -> String { String(format: "%.1f", value) }
}

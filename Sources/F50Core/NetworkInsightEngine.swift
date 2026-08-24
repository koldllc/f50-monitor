import Foundation

/// One normalized modem observation.  The engine does not infer a missing
/// radio metric; nil values are retained and reduce the confidence of a score.
public struct TelemetrySample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let online: Bool
    public let cellularConnected: Bool?
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
    /// Fetcher-level connection failure. This is intentionally kept separate
    /// from cellular radio state so Network Doctor does not blame the tower
    /// when the app simply cannot reach the device.
    public let localConnectionError: String?

    public init(
        timestamp: Date = Date(),
        online: Bool,
        cellularConnected: Bool? = nil,
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
        dataAgeSeconds: Double? = nil,
        localConnectionError: String? = nil
    ) {
        self.timestamp = timestamp
        self.online = online
        self.cellularConnected = cellularConnected
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
        self.localConnectionError = localConnectionError
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
    case baseStationSwitching
    case congestion
    case deviceOverheating
    case localConnection
    // Legacy values retained so reports saved by earlier releases still decode.
    case frequentSwitching
    case possibleOverheating
    case networkQuality
}

public enum DoctorTimelineEventKind: String, Codable, Equatable, Sendable {
    case disconnection
    case networkSwitch
    case cellularChange
    case sinrFluctuation
    case packetLoss
    case highLatency
    case highTemperature
    case localConnectionFailure
}

public struct DoctorTimelineEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let kind: DoctorTimelineEventKind
    public let summary: String

    public init(timestamp: Date, kind: DoctorTimelineEventKind, summary: String) {
        self.timestamp = timestamp
        self.kind = kind
        self.summary = summary
    }
}

public struct DoctorFinding: Codable, Equatable, Sendable {
    public let category: DoctorFindingCategory
    public let title: String
    public let summary: String
    public let evidence: [String]
    /// Evidence that lowers the probability of this cause. Optional for
    /// backwards-compatible decoding of reports saved by earlier releases.
    public let counterEvidence: [String]?
    public let confidence: Double

    public init(category: DoctorFindingCategory, title: String, summary: String, evidence: [String], counterEvidence: [String] = [], confidence: Double) {
        self.category = category
        self.title = title
        self.summary = summary
        self.evidence = evidence
        self.counterEvidence = counterEvidence
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
    public let timeline: [DoctorTimelineEvent]?
    public let counterEvidence: [String]?

    public init(start: Date?, end: Date?, sampleCount: Int, fiveGOnlineRate: Double, switchSummary: NetworkSwitchSummary, findings: [DoctorFinding], cellularChanges: [CellularChangeEvent]? = nil, timeline: [DoctorTimelineEvent]? = nil, counterEvidence: [String]? = nil) {
        self.start = start
        self.end = end
        self.sampleCount = sampleCount
        self.fiveGOnlineRate = fiveGOnlineRate
        self.switchSummary = switchSummary
        self.findings = findings
        self.cellularChanges = cellularChanges
        self.timeline = timeline
        self.counterEvidence = counterEvidence
    }

    public var primaryFinding: DoctorFinding? { findings.first }

    public func exportMarkdown(deviceAddress: String? = nil, includeSensitiveData: Bool = false) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["# F50 Network Doctor 诊断报告", ""]
        if let start { lines.append("- 开始：\(formatter.string(from: start))") }
        if let end { lines.append("- 结束：\(formatter.string(from: end))") }
        lines.append("- 采样：\(sampleCount) 次")
        lines.append("- 5G 在线率：\(Int((fiveGOnlineRate * 100).rounded()))%")
        lines.append("- 制式切换：\(switchSummary.total) 次")
        if includeSensitiveData, let deviceAddress, !deviceAddress.isEmpty {
            lines.append("- 设备地址：\(deviceAddress)")
        } else {
            lines.append("- 隐私：设备地址、Cell ID、PCI、TAC 默认隐藏")
        }
        lines.append(contentsOf: ["", "## 诊断结论", ""])
        if findings.isEmpty { lines.append("当前采样未发现明显异常。") }
        for finding in findings {
            lines.append("### \(finding.title)（可信度 \(Int((finding.confidence * 100).rounded()))%）")
            lines.append(finding.summary)
            for item in finding.evidence { lines.append("- 证据：\(item)") }
            for item in finding.counterEvidence ?? [] { lines.append("- 反证：\(item)") }
            lines.append("")
        }
        if let counterEvidence, !counterEvidence.isEmpty {
            lines.append(contentsOf: ["## 反证与较低可能性", ""])
            for item in counterEvidence { lines.append("- \(item)") }
            lines.append("")
        }
        if let timeline, !timeline.isEmpty {
            lines.append(contentsOf: ["## 关联时间线", ""])
            for event in timeline {
                let summary = includeSensitiveData ? event.summary : Self.redactSensitiveIdentity(in: event.summary)
                lines.append("- \(formatter.string(from: event.timestamp)) · \(summary)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func redactSensitiveIdentity(in value: String) -> String {
        var redacted = value
        if let separator = value.firstIndex(of: "：") {
            let label = String(value[..<separator])
            if ["Cell ID", "PCI", "TAC"].contains(label) {
                return "\(label)：[已隐藏]"
            }
        }
        let patterns = [
            #"https?://[^\s，。]+"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            redacted = regex.stringByReplacingMatches(in: redacted, range: NSRange(redacted.startIndex..., in: redacted), withTemplate: "[设备地址已隐藏]")
        }
        return redacted
    }
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
        let timeline = diagnosticTimeline(in: freshSamples, switchSummary: summary, cellularChanges: cellChanges)
        var findings: [DoctorFinding] = []
        guard !selected.isEmpty else {
            findings.append(DoctorFinding(category: .insufficientData, title: "数据不足", summary: "还没有可用于分析的网络采样。", evidence: [], confidence: 0))
            return DoctorReport(start: nil, end: nil, sampleCount: 0, fiveGOnlineRate: 0, switchSummary: summary, findings: findings)
        }

        guard !freshSamples.isEmpty else {
            findings.append(DoctorFinding(category: .insufficientData, title: "数据已陈旧", summary: "现有采样已经过期，暂时不能可靠判断网络原因。", evidence: ["请保持工具页在前台等待新数据"], confidence: 0))
            return DoctorReport(start: selected.first?.timestamp, end: selected.last?.timestamp, sampleCount: selected.count, fiveGOnlineRate: 0, switchSummary: summary, findings: findings, cellularChanges: cellChanges, timeline: timeline)
        }

        let rsrp = freshSamples.compactMap(\.rsrp)
        let snr = freshSamples.compactMap(\.snr)
        let avgRSRP = average(rsrp)
        let avgSNR = average(snr)
        let snrDeviation = standardDeviation(snr)
        let maxTemperature = freshSamples.compactMap(\.temperature).max()
        let loss = average(freshSamples.compactMap(\.packetLossPercent))
        let latency = average(freshSamples.compactMap(\.latencyMilliseconds))
        let packetLossEventCount = timeline.filter { $0.kind == .packetLoss }.count
        var reportCounterEvidence: [String] = []
        if let maxTemperature, maxTemperature < 60 {
            reportCounterEvidence.append("最高温度仅 \(format(maxTemperature)) ℃，因此设备过热可能性较低")
        }
        if let avgRSRP, avgRSRP >= -100 {
            reportCounterEvidence.append("平均 RSRP 为 \(format(avgRSRP)) dBm，因此覆盖不足可能性较低")
        }
        if summary.total + cellChanges.count == 0 {
            reportCounterEvidence.append("未确认制式、频段或小区切换，因此基站切换可能性较低")
        }

        if let avgRSRP, rsrp.count >= 3, avgRSRP < -105 {
            let weakRatio = Double(rsrp.filter { $0 < -105 }.count) / Double(rsrp.count)
            let confidence = min(0.95, 0.5 + weakRatio * 0.4)
            findings.append(DoctorFinding(
                category: .coverage,
                title: "覆盖不足",
                summary: "信号强度持续偏低，更可能是覆盖或摆放位置问题。",
                evidence: ["平均 RSRP：\(format(avgRSRP)) dBm", "弱信号占比：\(format(weakRatio * 100))%"],
                counterEvidence: normalTemperatureEvidence(maxTemperature),
                confidence: confidence
            ))
        }
        if let avgRSRP, let snrDeviation, rsrp.count >= 3, snr.count >= 4, snrDeviation >= 5 {
            let stableRSRP = (standardDeviation(rsrp) ?? 100) < 5
            if stableRSRP {
                var evidence = ["平均 RSRP：\(format(avgRSRP)) dBm", "SINR/SNR 标准差：\(format(snrDeviation)) dB"]
                let lossNearSINR = correlatedCount(primary: timeline.filter { $0.kind == .sinrFluctuation }, secondary: timeline.filter { $0.kind == .packetLoss }, within: 30)
                if lossNearSINR > 0 { evidence.append("SINR 波动前后 30 秒出现丢包：\(lossNearSINR) 次") }
                findings.append(DoctorFinding(category: .interference, title: "无线干扰", summary: "RSRP 相对稳定，但 SINR/SNR 波动较大，更可能是无线干扰。", evidence: evidence, counterEvidence: normalTemperatureEvidence(maxTemperature), confidence: min(0.9, 0.5 + snrDeviation / 20 + Double(lossNearSINR) * 0.05)))
            }
        }

        let totalChanges = summary.total + cellChanges.count
        let changes = timeline.filter { $0.kind == .networkSwitch || $0.kind == .cellularChange }
        let disruptions = timeline.filter { [.disconnection, .packetLoss, .highLatency].contains($0.kind) }
        let disruptionsNearChanges = correlatedCount(primary: changes, secondary: disruptions, within: 30)
        if totalChanges >= 2 || (totalChanges >= 1 && disruptionsNearChanges > 0) {
            let bandChanges = cellChanges.filter { $0.kind == .band }.count
            let identityChanges = cellChanges.filter { $0.kind == .pci || $0.kind == .cellId }.count
            var evidence = ["制式切换：\(summary.total) 次", "频段切换：\(bandChanges) 次", "小区标识切换：\(identityChanges) 次"]
            if disruptionsNearChanges > 0 { evidence.append("切换前后 30 秒伴随掉线、丢包或高延迟：\(disruptionsNearChanges) 次") }
            findings.append(DoctorFinding(category: .baseStationSwitching, title: "基站切换", summary: "已确认制式、频段或小区变化；与网络异常同时出现时，更可能影响稳定性。", evidence: evidence, counterEvidence: disruptionsNearChanges == 0 ? ["切换前后未观察到掉线、丢包或高延迟，切换未必是故障原因"] : [], confidence: min(0.95, 0.45 + Double(totalChanges) * 0.08 + Double(disruptionsNearChanges) * 0.1)))
        }

        if let maxTemperature, maxTemperature >= 65 {
            let thermalEvents = timeline.filter { $0.kind == .highTemperature }
            let thermalDisruptions = correlatedCount(primary: thermalEvents, secondary: disruptions, within: 60)
            var evidence = ["最高温度：\(format(maxTemperature)) ℃"]
            if thermalDisruptions > 0 { evidence.append("高温前后 60 秒伴随丢包、掉线或高延迟：\(thermalDisruptions) 次") }
            findings.append(DoctorFinding(category: .deviceOverheating, title: "设备过热", summary: "设备温度偏高；只有与性能异常在时间上重合时，过热原因才更可信。", evidence: evidence, counterEvidence: thermalDisruptions == 0 ? ["高温时段未观察到网络性能异常，暂不能证明因果关系"] : [], confidence: min(0.9, 0.45 + (maxTemperature - 65) / 50 + Double(thermalDisruptions) * 0.1)))
        }

        if let avgRSRP, avgRSRP >= -100, (avgSNR ?? 8) >= 5, ((latency ?? 0) >= 120 || ((loss ?? 0) >= 10 && packetLossEventCount >= 2)) {
            var evidence = ["平均 RSRP：\(format(avgRSRP)) dBm"]
            if let avgSNR { evidence.append("平均 SINR/SNR：\(format(avgSNR)) dB") }
            if let latency { evidence.append("平均延迟：\(format(latency)) ms") }
            if let loss { evidence.append("平均丢包：\(format(loss))%") }
            let qualityEvents = timeline.filter { $0.kind == .packetLoss || $0.kind == .highLatency }
            let qualityNearSwitches = correlatedCount(primary: qualityEvents, secondary: changes, within: 30)
            findings.append(DoctorFinding(category: .congestion, title: "网络拥塞", summary: "无线信号尚可，但延迟或丢包偏高；若异常不紧邻切换，更可能是拥塞、回程或上层网络问题。", evidence: evidence, counterEvidence: qualityNearSwitches > 0 ? ["部分质量异常紧邻基站切换，拥塞并非唯一解释"] : normalTemperatureEvidence(maxTemperature), confidence: qualityNearSwitches > 0 ? 0.55 : 0.72))
        }

        let localFailures = timeline.filter { $0.kind == .localConnectionFailure }
        if !localFailures.isEmpty {
            let nearbyRadioChanges = correlatedCount(primary: localFailures, secondary: changes, within: 30)
            var evidence = ["本地连接中断：\(localFailures.count) 次"]
            if freshSamples.contains(where: { $0.localConnectionError != nil }) { evidence.append("设备抓取器返回了本地连接错误") }
            findings.append(DoctorFinding(category: .localConnection, title: "本地连接异常", summary: "App 在诊断时段无法稳定连接 F50；这与蜂窝侧掉线是不同问题。", evidence: evidence, counterEvidence: nearbyRadioChanges > 0 ? ["中断附近也发生了基站切换，可能同时存在蜂窝侧波动"] : [], confidence: freshSamples.contains(where: { $0.localConnectionError != nil }) ? 0.88 : 0.65))
        }
        return makeDoctorReport(selected: freshSamples, summary: summary, findings: findings, cellularChanges: cellChanges, timeline: timeline, counterEvidence: reportCounterEvidence)
    }

    private func makeDoctorReport(selected: [TelemetrySample], summary: NetworkSwitchSummary, findings: [DoctorFinding], cellularChanges: [CellularChangeEvent], timeline: [DoctorTimelineEvent], counterEvidence: [String]) -> DoctorReport {
        let sortedFindings = findings.sorted { $0.confidence > $1.confidence }
        let dates = selected.map(\.timestamp)
        return DoctorReport(start: dates.min(), end: dates.max(), sampleCount: selected.count, fiveGOnlineRate: fiveGRate(in: selected), switchSummary: summary, findings: sortedFindings, cellularChanges: cellularChanges, timeline: timeline, counterEvidence: counterEvidence)
    }

    private func diagnosticTimeline(
        in values: [TelemetrySample],
        switchSummary: NetworkSwitchSummary,
        cellularChanges: [CellularChangeEvent]
    ) -> [DoctorTimelineEvent] {
        let ordered = values.sorted { $0.timestamp < $1.timestamp }
        var events = switchSummary.events.map {
            DoctorTimelineEvent(timestamp: $0.timestamp, kind: .networkSwitch, summary: "制式切换：\($0.from) → \($0.to)")
        }
        events += cellularChanges.map {
            let label: String
            switch $0.kind {
            case .band: label = "频段"
            case .pci: label = "PCI"
            case .cellId: label = "Cell ID"
            case .tac: label = "TAC"
            }
            return DoctorTimelineEvent(timestamp: $0.timestamp, kind: .cellularChange, summary: "\(label)：\($0.from) → \($0.to)")
        }

        var previous: TelemetrySample?
        var highTemperatureActive = false
        for sample in ordered {
            if let previous {
                if previous.cellularConnected == true, sample.cellularConnected == false {
                    events.append(DoctorTimelineEvent(timestamp: sample.timestamp, kind: .disconnection, summary: "蜂窝数据连接掉线"))
                }
                if previous.online, !sample.online {
                    let message = sample.localConnectionError?.trimmingCharacters(in: .whitespacesAndNewlines)
                    events.append(DoctorTimelineEvent(timestamp: sample.timestamp, kind: .localConnectionFailure, summary: message.map { "本地连接失败：\($0)" } ?? "App 无法连接 F50"))
                }
                if let old = previous.snr, let current = sample.snr, abs(current - old) >= 6 {
                    events.append(DoctorTimelineEvent(timestamp: sample.timestamp, kind: .sinrFluctuation, summary: "SINR/SNR 突变 \(format(old)) → \(format(current)) dB"))
                }
            }
            if let loss = sample.packetLossPercent, loss >= 3 {
                events.append(DoctorTimelineEvent(timestamp: sample.timestamp, kind: .packetLoss, summary: "丢包 \(format(loss))%"))
            }
            if let latency = sample.latencyMilliseconds, latency >= 120 {
                events.append(DoctorTimelineEvent(timestamp: sample.timestamp, kind: .highLatency, summary: "延迟 \(format(latency)) ms"))
            }
            let isHighTemperature = (sample.temperature ?? 0) >= 65
            if isHighTemperature, !highTemperatureActive, let temperature = sample.temperature {
                events.append(DoctorTimelineEvent(timestamp: sample.timestamp, kind: .highTemperature, summary: "设备温度升至 \(format(temperature)) ℃"))
            }
            highTemperatureActive = isHighTemperature
            previous = sample
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func correlatedCount(primary: [DoctorTimelineEvent], secondary: [DoctorTimelineEvent], within seconds: TimeInterval) -> Int {
        primary.reduce(0) { count, event in
            count + (secondary.contains { abs($0.timestamp.timeIntervalSince(event.timestamp)) <= seconds } ? 1 : 0)
        }
    }

    private func normalTemperatureEvidence(_ maxTemperature: Double?) -> [String] {
        guard let maxTemperature, maxTemperature < 60 else { return [] }
        return ["最高温度仅 \(format(maxTemperature)) ℃，过热可能性较低"]
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
            cellularConnected: latest.cellularConnected,
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
            dataAgeSeconds: latest.dataAgeSeconds,
            localConnectionError: latest.localConnectionError
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

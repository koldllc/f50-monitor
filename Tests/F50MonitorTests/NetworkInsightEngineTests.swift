import XCTest
@testable import F50Core

final class NetworkInsightEngineTests: XCTestCase {
    private func sample(
        _ second: TimeInterval,
        network: String = "5G SA",
        rsrp: Double? = -92,
        snr: Double? = 13,
        rsrq: Double? = -10,
        online: Bool = true,
        temperature: Double? = 40,
        latency: Double? = 30,
        loss: Double? = 0,
        download: Double = 100
    ) -> TelemetrySample {
        TelemetrySample(
            timestamp: Date(timeIntervalSince1970: second),
            online: online,
            networkType: network,
            rsrp: rsrp,
            rsrq: rsrq,
            snr: snr,
            band: "n78",
            temperature: temperature,
            downloadBytesPerSecond: download,
            latencyMilliseconds: latency,
            packetLossPercent: loss
        )
    }

    func testScoreUsesConfiguredWeightsAndMissingMetricsReduceConfidence() {
        let engine = NetworkInsightEngine()
        let complete = engine.signalScore(for: sample(0))
        XCTAssertEqual(complete.value, 60) // RSRP 70, SNR 51, RSRQ 59: weighted average.
        XCTAssertEqual(complete.confidence, 1, accuracy: 0.001)

        let missing = engine.signalScore(for: sample(0, rsrp: -92, snr: nil, rsrq: -10))
        XCTAssertEqual(missing.confidence, 0.6, accuracy: 0.001)
        XCTAssertEqual(missing.value, 66) // Missing SNR reweights RSRP/RSRQ to 40/20.
    }

    func testTrendIsDebouncedUntilTheWindowMovesClearly() {
        let stable = NetworkInsightEngine(samples: (0..<6).map { sample(Double($0), rsrp: -92, snr: 13) })
        XCTAssertEqual(stable.liveInsight.trend, .stable)

        let improving = NetworkInsightEngine(samples: (0..<6).map {
            let offset = $0 < 3 ? 0 : 12
            return sample(Double($0), rsrp: -92 + Double(offset), snr: 13 + Double(offset))
        })
        XCTAssertEqual(improving.liveInsight.trend, .up)
    }

    func testLocationComparisonRanksByScoreAndReportsDownloadImprovement() {
        let engine = NetworkInsightEngine()
        let window = (0..<4).map { sample(Double($0), rsrp: -85, snr: 20, rsrq: -7, download: 200) }
        let desk = (0..<4).map { sample(Double($0), rsrp: -105, snr: 3, rsrq: -15, download: 100) }
        let comparison = engine.compareLocations([
            engine.makeLocationReport(name: "桌面", samples: desk),
            engine.makeLocationReport(name: "窗边", samples: window)
        ])
        XCTAssertEqual(comparison.bestLocationName, "窗边")
        XCTAssertEqual(comparison.locations.first?.name, "窗边")
        XCTAssertEqual(comparison.downloadImprovementPercent ?? -1, 100, accuracy: 0.001)
    }

    func testDoctorCountsSwitchesAndUsesEvidenceForLikelyInterference() {
        let networks = ["5G SA", "4G LTE", "5G SA", "4G LTE", "5G SA"]
        let samples = networks.enumerated().flatMap { group, network in
            (0..<3).map { index in
                let second = Double(group * 6 + index * 2)
                return sample(second, network: network, snr: group.isMultiple(of: 2) ? 2 : 19)
            }
        }
        let report = NetworkInsightEngine(samples: samples).diagnose(window: DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(report.switchSummary.total, 4)
        XCTAssertEqual(report.switchSummary.fiveGToLTE, 2)
        XCTAssertEqual(report.switchSummary.lteToFiveG, 2)
        XCTAssertTrue(report.findings.contains { $0.category == .frequentSwitching })
        XCTAssertTrue(report.findings.contains { $0.category == .interference })
        XCTAssertTrue(report.findings.allSatisfy { $0.summary.contains("可能") || $0.summary.contains("更可能") || $0.summary.contains("不能证明") })
    }

    func testDoctorIgnoresSingleSampleNetworkFlap() {
        let samples = [
            sample(0, network: "5G SA"),
            sample(2, network: "5G SA"),
            sample(4, network: "4G LTE"),
            sample(6, network: "5G SA"),
            sample(8, network: "5G SA")
        ]
        let report = NetworkInsightEngine(samples: samples).diagnose()
        XCTAssertEqual(report.switchSummary.total, 0)
    }

    func testDoctorSeparatesPossibleOverheatingFromRadioQuality() {
        let report = NetworkInsightEngine(samples: [
            sample(0, temperature: 70), sample(1, temperature: 72), sample(2, temperature: 71)
        ]).diagnose()
        XCTAssertTrue(report.findings.contains { $0.category == .possibleOverheating })
        XCTAssertFalse(report.findings.contains { $0.category == .coverage })
    }
}

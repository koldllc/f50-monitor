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
        cellularConnected: Bool? = true,
        temperature: Double? = 40,
        latency: Double? = 30,
        loss: Double? = 0,
        download: Double = 100,
        band: String? = "n78",
        pci: String? = nil,
        cellId: String? = nil,
        tac: String? = nil,
        withSources: Bool = false,
        dataAge: Double? = nil,
        localConnectionError: String? = nil
    ) -> TelemetrySample {
        TelemetrySample(
            timestamp: Date(timeIntervalSince1970: second),
            online: online,
            cellularConnected: cellularConnected,
            networkType: network,
            rsrp: rsrp,
            rsrq: rsrq,
            snr: snr,
            band: band,
            temperature: temperature,
            downloadBytesPerSecond: download,
            latencyMilliseconds: latency,
            packetLossPercent: loss,
            pci: pci,
            cellId: cellId,
            tac: tac,
            rsrpSource: withSources ? "nr_rsrp" : nil,
            rsrqSource: withSources ? "nr_rsrq" : nil,
            snrSource: withSources ? "nr_sinr" : nil,
            snrKind: withSources ? .sinr : .unknown,
            dataAgeSeconds: dataAge,
            localConnectionError: localConnectionError
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

    func testScoreExposesSubscoresSourcesAndStaleConfidence() {
        let engine = NetworkInsightEngine()
        let fresh = engine.signalScore(for: sample(0, withSources: true))
        XCTAssertNotNil(fresh.strengthScore)
        XCTAssertNotNil(fresh.interferenceScore)
        XCTAssertEqual(fresh.sourceCoverage, 1, accuracy: 0.001)
        XCTAssertFalse(fresh.isStale)

        let stale = engine.signalScore(for: sample(0, withSources: true, dataAge: 45))
        XCTAssertTrue(stale.isStale)
        XCTAssertEqual(stale.confidence, 0.2, accuracy: 0.001)
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
        XCTAssertTrue(report.findings.contains { $0.category == .baseStationSwitching })
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

    func testDoctorConfirmsBandAndCellChangesAfterThreeSamples() {
        let samples = [
            sample(0, band: "n78", pci: "100", cellId: "A"),
            sample(2, band: "n78", pci: "100", cellId: "A"),
            sample(4, band: "n78", pci: "100", cellId: "A"),
            sample(6, band: "n41", pci: "200", cellId: "B"),
            sample(8, band: "n41", pci: "200", cellId: "B"),
            sample(10, band: "n41", pci: "200", cellId: "B")
        ]
        let report = NetworkInsightEngine(samples: samples).diagnose()
        XCTAssertEqual(report.cellularChanges?.filter { $0.kind == .band }.count, 1)
        XCTAssertEqual(report.cellularChanges?.filter { $0.kind == .pci }.count, 1)
        XCTAssertEqual(report.cellularChanges?.filter { $0.kind == .cellId }.count, 1)
    }

    func testDoctorSeparatesPossibleOverheatingFromRadioQuality() {
        let report = NetworkInsightEngine(samples: [
            sample(0, temperature: 70), sample(1, temperature: 72), sample(2, temperature: 71)
        ]).diagnose()
        XCTAssertTrue(report.findings.contains { $0.category == .deviceOverheating })
        XCTAssertFalse(report.findings.contains { $0.category == .coverage })
    }

    func testDoctorCorrelatesSwitchSINRAndPacketLossOnOneTimeline() {
        let samples = [
            sample(0, network: "5G SA", snr: 18, loss: 0, cellId: "A"),
            sample(5, network: "5G SA", snr: 3, loss: 20, cellId: "A"),
            sample(10, network: "4G LTE", snr: 17, loss: 15, cellId: "B"),
            sample(15, network: "4G LTE", snr: 2, loss: 0, cellId: "B"),
            sample(20, network: "4G LTE", snr: 18, loss: 0, cellId: "B")
        ]
        let report = NetworkInsightEngine(samples: samples).diagnose()
        XCTAssertTrue(report.timeline?.contains { $0.kind == .sinrFluctuation } == true)
        XCTAssertTrue(report.timeline?.contains { $0.kind == .packetLoss } == true)
        XCTAssertTrue(report.timeline?.contains { $0.kind == .networkSwitch } == true)
        XCTAssertTrue(report.findings.contains { finding in
            finding.category == .baseStationSwitching && finding.evidence.contains { $0.contains("前后 30 秒") }
        })
    }

    func testDoctorShowsNormalTemperatureAsCounterEvidence() {
        let report = NetworkInsightEngine(samples: (0..<4).map {
            sample(Double($0), rsrp: -112, temperature: 43)
        }).diagnose()
        XCTAssertTrue(report.findings.contains { $0.category == .coverage })
        XCTAssertTrue(report.counterEvidence?.contains { $0.contains("过热可能性较低") } == true)
    }

    func testDoctorSeparatesCongestionAndLocalConnectionFailure() {
        let congestion = NetworkInsightEngine(samples: (0..<4).map {
            sample(Double($0 * 5), rsrp: -90, snr: 15, latency: 180, loss: 12)
        }).diagnose()
        XCTAssertTrue(congestion.findings.contains { $0.category == .congestion })

        let local = NetworkInsightEngine(samples: [
            sample(0),
            sample(5, online: false, localConnectionError: "无法连接 http://192.168.0.1")
        ]).diagnose()
        XCTAssertTrue(local.findings.contains { $0.category == .localConnection })
    }

    func testDoctorExportHidesSensitiveDataByDefault() {
        let report = NetworkInsightEngine(samples: [
            sample(0, cellId: "CELL-SECRET", tac: "TAC-SECRET"),
            sample(1, cellId: "CELL-SECRET", tac: "TAC-SECRET"),
            sample(2, cellId: "CELL-SECRET", tac: "TAC-SECRET"),
            sample(3, cellId: "CELL-OTHER", tac: "TAC-OTHER"),
            sample(4, cellId: "CELL-OTHER", tac: "TAC-OTHER"),
            sample(5, cellId: "CELL-OTHER", tac: "TAC-OTHER")
        ]).diagnose()
        let safe = report.exportMarkdown(deviceAddress: "192.168.0.1")
        XCTAssertFalse(safe.contains("CELL-SECRET"))
        XCTAssertFalse(safe.contains("TAC-SECRET"))
        XCTAssertFalse(safe.contains("192.168.0.1"))

        let full = report.exportMarkdown(deviceAddress: "192.168.0.1", includeSensitiveData: true)
        XCTAssertTrue(full.contains("CELL-SECRET"))
        XCTAssertTrue(full.contains("192.168.0.1"))
    }

    func testAnonymizedFieldFaultReplaysKeepExpectedRulesStable() throws {
        struct Fixture: Decodable {
            struct Replay: Decodable {
                struct Point: Decodable {
                    let second: Double
                    let online: Bool
                    let cellularConnected: Bool?
                    let network: String
                    let rsrp: Double?
                    let snr: Double?
                    let temperature: Double?
                    let latency: Double?
                    let loss: Double?
                    let cellId: String?
                    let localConnectionError: String?
                }
                let name: String
                let expectedCategories: [DoctorFindingCategory]
                let samples: [Point]
            }
            let replays: [Replay]
        }

        let url = try XCTUnwrap(Bundle.module.url(forResource: "network_doctor_field_replays", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        for replay in fixture.replays {
            let samples = replay.samples.map { point in
                sample(point.second, network: point.network, rsrp: point.rsrp, snr: point.snr, online: point.online, cellularConnected: point.cellularConnected, temperature: point.temperature, latency: point.latency, loss: point.loss, cellId: point.cellId, localConnectionError: point.localConnectionError)
            }
            let categories = Set(NetworkInsightEngine(samples: samples).diagnose().findings.map(\.category))
            for expected in replay.expectedCategories {
                XCTAssertTrue(categories.contains(expected), "\(replay.name) 应命中 \(expected.rawValue)，实际为 \(categories)")
            }
        }
    }
}

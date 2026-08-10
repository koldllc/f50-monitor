import XCTest
@testable import F50Monitor

final class F50ResponseParserTests: XCTestCase {
    func testDefaultsUseAdminForBothCredentials() {
        XCTAssertEqual(F50Configuration.defaultCredential, "admin")
    }

    func testParsesQosResponse() {
        let parsed = F50ResponseParser.parseQos(
            "*+CGEQOSRDP: 1,8,0,0,0,0,500000,60000 OK"
        )

        XCTAssertEqual(parsed, ParsedQos(qci: "8", downlink: "500Mbps", uplink: "60Mbps"))
    }

    func testRejectsMalformedQosResponse() {
        XCTAssertNil(F50ResponseParser.parseQos("ERROR"))
    }

    func testDisconnectedIsNotMisclassifiedAsConnected() {
        XCTAssertEqual(F50ResponseParser.parsePPPStatus("disconnected"), "未连接")
        XCTAssertEqual(F50ResponseParser.parsePPPStatus("connected"), "已连接")
    }

    func testParsesNumericValuesFromRouterPayloads() {
        XCTAssertEqual(F50ResponseParser.parseInt("bars: 5"), 5)
        XCTAssertEqual(F50ResponseParser.parseDouble("61.5℃"), 61.5)
        XCTAssertEqual(F50ResponseParser.parseUInt64("12345 bytes"), 12345)
    }

    func testParsesTrafficLimitFromRouterPayload() {
        XCTAssertEqual(
            F50ResponseParser.parseTrafficLimit(size: "1536_1", unit: "data"),
            1536 * 1024 * 1024
        )
        XCTAssertEqual(F50ResponseParser.parseTrafficLimit(size: "1536", unit: "time"), 0)
    }

    func testFormatsTerabytes() {
        XCTAssertEqual(F50Status.formatBytes(1536 * 1024 * 1024 * 1024), "1.50 TB")
    }

    func testParsesCurrentBandsForNetworkType() {
        let payload: [String: Any] = [
            "wan_active_band": "LTE BAND 3",
            "nr5g_action_band": "n78"
        ]

        XCTAssertEqual(F50ResponseParser.parseCurrentBands(from: payload, networkType: "5G NSA"), "B3 + n78")
        XCTAssertEqual(F50ResponseParser.parseCurrentBands(from: payload, networkType: "5G SA"), "n78")
        XCTAssertEqual(F50ResponseParser.parseCurrentBands(from: payload, networkType: "4G LTE"), "B3")
    }

    func testBaseRefreshKeepsExistingHardwareMetricsWhenPayloadHasNoValidValues() {
        var status = F50Status()
        status.cpuUsage = 32
        status.memUsage = 60
        status.temperature = 61.4

        status.mergeHardwareMetrics(from: [
            "cpu_utility": 0,
            "mem_utility": "0",
            "ic_temp": NSNull()
        ])

        XCTAssertEqual(status.cpuUsage, 32)
        XCTAssertEqual(status.memUsage, 60)
        XCTAssertEqual(status.temperature, 61.4)
    }

    func testBaseRefreshUpdatesHardwareMetricsWhenPayloadHasValidValues() {
        var status = F50Status()
        status.cpuUsage = 32
        status.memUsage = 60
        status.temperature = 61.4

        status.mergeHardwareMetrics(from: [
            "cpu_utility": 41,
            "mem_utility": "72.5",
            "ic_temp": "63.2℃"
        ])

        XCTAssertEqual(status.cpuUsage, 41)
        XCTAssertEqual(status.memUsage, 72.5)
        XCTAssertEqual(status.temperature, 63.2)
    }

    func testConfigurationChangeClearsHardwareMetrics() {
        var status = F50Status()
        status.cpuUsage = 32
        status.memUsage = 60
        status.temperature = 61.4

        status.clearHardwareMetrics()

        XCTAssertEqual(status.cpuUsage, 0)
        XCTAssertEqual(status.memUsage, 0)
        XCTAssertEqual(status.temperature, 0)
    }
}

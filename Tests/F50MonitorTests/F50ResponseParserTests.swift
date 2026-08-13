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
        XCTAssertEqual(F50ResponseParser.parseUInt64(NSNumber(value: 9876543210 as UInt64)), 9876543210)
        XCTAssertEqual(F50ResponseParser.parseUInt64("0x1000"), 4096)
        XCTAssertEqual(F50ResponseParser.parseUInt64(123.456), 123)
    }

    func testSumsCellularUsageRowsFromUFIBackend() {
        let payload: [String: Any] = [
            "result": "success",
            "usage": [
                ["date": "2026-08-09", "usage": "51324645852"],
                ["date": "2026-08-10", "usage": "15600173859"]
            ]
        ]

        XCTAssertEqual(F50ResponseParser.parseCellularUsage(payload), 66_924_819_711)
        XCTAssertEqual(F50ResponseParser.parseCellularUsage(["result": "success", "usage": []]), 0)
        XCTAssertNil(F50ResponseParser.parseCellularUsage(["result": "failed"]))
    }

    func testParsesBase64EncodedSMSMessages() {
        let payload: [String: Any] = [
            "messages": [[
                "id": 42,
                "number": "10086",
                "content": Data("验证码 123456".utf8).base64EncodedString(),
                "date": "2026,08,13,14,25,09,+08",
                "tag": "1"
            ]]
        ]

        XCTAssertEqual(
            F50ResponseParser.parseSMSMessages(payload),
            [F50SMSMessage(
                id: "42",
                number: "10086",
                content: "验证码 123456",
                dateText: "2026-08-13 14:25:09",
                tag: "1"
            )]
        )
    }

    func testNormalizesUFIBaseDeviceInfoAliases() {
        let normalized = F50ResponseParser.normalizeUFIPayload([
            "battery": 86,
            "cpu_temp": 60_620,
            "daily_data": "1024",
            "monthly_data": "4096",
            "client_count": 3,
            "operator": "中国联通",
            "network_mode": "5G SA"
        ])

        XCTAssertEqual(F50ResponseParser.parseInt(normalized["battery_value"] ?? 0), 86)
        XCTAssertEqual(F50ResponseParser.parseDouble(normalized["cpu_temp"] ?? 0), 60.62, accuracy: 0.001)
        XCTAssertEqual(F50ResponseParser.parseUInt64(normalized["day_rx_bytes"] ?? 0), 1024)
        XCTAssertEqual(F50ResponseParser.parseUInt64(normalized["monthly_rx_bytes"] ?? 0), 4096)
        XCTAssertEqual(F50ResponseParser.parseInt(normalized["wifi_access_sta_num"] ?? 0), 3)
        XCTAssertEqual(normalized["network_provider"] as? String, "中国联通")
        XCTAssertEqual(normalized["network_type"] as? String, "5G SA")
    }

    func testParsesTrafficLimitFromRouterPayload() {
        XCTAssertEqual(
            F50ResponseParser.parseTrafficLimit(size: "1536_1", unit: "data"),
            1536 * 1024 * 1024
        )
        XCTAssertEqual(
            F50ResponseParser.parseTrafficLimit(size: "100_1024", unit: "0"),
            100 * 1024 * 1024 * 1024
        )
        XCTAssertEqual(
            F50ResponseParser.parseTrafficLimit(size: "10", unit: "GB"),
            10 * 1024 * 1024 * 1024
        )
        XCTAssertEqual(
            F50ResponseParser.parseTrafficLimit(size: "500", unit: "MB"),
            500 * 1024 * 1024
        )
        XCTAssertEqual(F50ResponseParser.parseTrafficLimit(size: "0", unit: "data"), 0)
    }

    func testF50StatusTrafficTotals() {
        var status = F50Status()
        status.monthlyRx = 1000
        status.monthlyTx = 500
        status.realtimeRx = 200
        status.realtimeTx = 100
        status.trackedDaily = 400

        XCTAssertEqual(status.monthlyTotal, 1500)
        XCTAssertEqual(status.sessionTotal, 300)
        XCTAssertEqual(status.dailyTotal, 400)

        status.dailyRx = 250
        status.dailyTx = 250
        XCTAssertEqual(status.dailyTotal, 500)
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

        XCTAssertEqual(
            F50ResponseParser.parseCurrentBands(
                from: ["ZCELLINFO_band": "78"],
                networkType: "5G SA"
            ),
            "n78"
        )
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

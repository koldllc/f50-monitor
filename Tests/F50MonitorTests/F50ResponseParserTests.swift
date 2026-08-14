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
        // daily_data/monthly_data 是“自某时刻起的累计”，不再复制进 day_rx_bytes/monthly_rx_bytes
        // （当日/本月统一由 /api/cellularUsage 按日期区间查询）
        XCTAssertNil(normalized["day_rx_bytes"])
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

    func testExtractsResetDayFromDayKeysUsedByZTERouter() {
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: ["data_volume_clear_day": "16"]), 16)
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: ["monthly_clear_day": "1"]), 1)
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: ["clear_day": 25]), 25)
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: ["billing_day": "31"]), 31)
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: ["data_volume_clear_day": "0"]), 0)
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: [:]), 0)
    }

    func testExtractsResetDayFromFullDateValues() {
        XCTAssertEqual(
            F50ResponseParser.extractFirstValidResetDay(from: ["data_volume_clear_date": "2026-08-16"]), 16)
        XCTAssertEqual(
            F50ResponseParser.extractFirstValidResetDay(from: ["clear_date": "2026/8/16"]), 16)
        XCTAssertEqual(
            F50ResponseParser.extractFirstValidResetDay(from: ["billing_date": "2026年8月16日"]), 16)
        // 无效/占位值应被忽略
        XCTAssertEqual(
            F50ResponseParser.extractFirstValidResetDay(from: ["data_volume_clear_date": "0"]), 0)
        XCTAssertEqual(
            F50ResponseParser.extractFirstValidResetDay(from: ["clear_date": NSNull()]), 0)
    }

    func testExtractsResetDayFromTrafficClearDateField() {
        // F50 设备（80/2333 后台）实际使用的字段
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: ["traffic_clear_date": "18"]), 18)
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: ["traffic_clear_date": 18]), 18)
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: ["traffic_clear_date": "2026-08-18"]), 18)
        XCTAssertEqual(
            F50ResponseParser.extractFirstValidResetDay(from: ["traffic_clear_date": "0"]), 0)
    }

    func testUFIPayloadNormalizationPreservesResetDay() {
        let payload = F50ResponseParser.normalizeUFIPayload(["data_volume_clear_day": "16"])
        XCTAssertEqual(F50ResponseParser.extractFirstValidResetDay(from: payload), 16)
    }

    func testDaysUntilResetIsNilWhenResetDayUnknown() {
        let status = F50Status() // trafficResetDay == 0（未知）
        XCTAssertNil(status.daysUntilReset)
    }

    func testDaysUntilResetMatchesExplicitResetDay() {
        var status = F50Status()
        status.trafficResetDay = 16
        guard let days = status.daysUntilReset else {
            XCTFail("显式设置清零日后应返回天数")
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentDay = calendar.component(.day, from: today)
        let resetDay = 16

        let target: Date
        if currentDay <= resetDay {
            var comps = calendar.dateComponents([.year, .month], from: today)
            let range = calendar.range(of: .day, in: .month, for: today) ?? 1..<31
            comps.day = min(resetDay, range.count)
            target = calendar.date(from: comps) ?? today
        } else {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) else {
                XCTFail("无法计算下月日期")
                return
            }
            var comps = calendar.dateComponents([.year, .month], from: nextMonth)
            let range = calendar.range(of: .day, in: .month, for: nextMonth) ?? 1..<31
            comps.day = min(resetDay, range.count)
            target = calendar.date(from: comps) ?? today
        }
        let expected = max(0, calendar.dateComponents([.day], from: today, to: target).day ?? 0)
        XCTAssertEqual(days, expected)
    }

    func testFormatsTerabytes() {
        XCTAssertEqual(F50Status.formatBytes(1536 * 1024 * 1024 * 1024), "1.50 TB")
    }

    func testGSMEncodeMatchesUFIUTF16BEHex() {
        // UFI-TOOLS 短信编码 = UTF-16BE 的 hex（非 GSM 7-bit）
        XCTAssertEqual(F50ResponseParser.gsmEncode("A"), "0041")
        XCTAssertEqual(F50ResponseParser.gsmEncode("hello"), "00680065006c006c006f")
        // 中文“测” U+6D4B
        XCTAssertEqual(F50ResponseParser.gsmEncode("测"), "6d4b")
        // 混合：测=6D4B 试=8BD5 空格=0020 hello
        XCTAssertEqual(F50ResponseParser.gsmEncode("测试 hello"), "6d4b8bd5002000680065006c006c006f")
        // 完整对照 python 验证值（与 UFI 后台一致）
        XCTAssertEqual(
            F50ResponseParser.gsmEncode("测试短信 hello"),
            "6d4b8bd577ed4fe1002000680065006c006c006f"
        )
        XCTAssertEqual(F50ResponseParser.gsmEncode(""), "")
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

    func testMonthlyTotalClampsHugeValuesWithoutCrash() {
        var status = F50Status()
        // 设备脏数据：UInt64.max，直接 Int64 转换会 trap
        status.monthlyRx = UInt64.max
        status.monthlyTx = 0
        status.monthlyOffsetBytes = -1
        XCTAssertGreaterThan(status.monthlyTotal, 0)
    }

    func testTrafficUsageRatioPrefersPackageTotal() {
        var status = F50Status()
        // 套餐账单周期累计（Router 80 端口）优先于 UFI 月度值
        status.packageRx = 138 * 1024 * 1024 * 1024
        status.packageTx = 2 * 1024 * 1024 * 1024
        status.monthlyRx = 7 * 1024 * 1024 * 1024
        status.monthlyTx = 0
        status.trafficLimit = 350 * 1024 * 1024 * 1024

        // ratio 基于 packageTotal (140GB)，而非 UFI 月度值 (7GB)
        XCTAssertEqual(status.packageTotal, 140 * 1024 * 1024 * 1024)
        XCTAssertEqual(status.trafficUsageRatio, 0.4, accuracy: 0.001)
    }

    func testTrafficUsageRatioFallsBackToMonthlyTotalWithoutPackageData() {
        var status = F50Status()
        status.monthlyRx = 10 * 1024 * 1024 * 1024
        status.monthlyTx = 0
        status.monthlyOffsetBytes = 5 * 1024 * 1024 * 1024 // 校准 +5GB
        status.trafficLimit = 20 * 1024 * 1024 * 1024

        // 无套餐数据时回退 monthlyTotal（含校准偏移）
        XCTAssertEqual(status.packageTotal, 0)
        XCTAssertEqual(status.trafficUsageRatio, 0.75, accuracy: 0.001)
    }

    func testTrafficUsageRatioClampsToRange() {
        var status = F50Status()
        status.packageRx = 30 * 1024 * 1024 * 1024
        status.trafficLimit = 20 * 1024 * 1024 * 1024
        XCTAssertEqual(status.trafficUsageRatio, 1.0)
        XCTAssertEqual(F50Status().trafficUsageRatio, 0.0)
    }
}

import XCTest
import CryptoKit
@testable import F50Core

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

    func testDecodesQosFromADBServiceParcel() {
        let parcel = """
        Result: Parcel(
          0x00000000: 00000000 0000002b 0043002b 00450047
          0x00000010: 004f0051 00520053 00500044 0020003a
          0x00000020: 002c0031 002c0038 002c0030 002c0030
          0x00000030: 002c0030 002c0030 00300035 00300030
          0x00000040: 00300030 0031002c 00300030 00300030
          0x00000050: 000d0030 004f000a 000d004b 0000000a
        )
        """

        let decoded = ADBHardwareFetcher.decodeBinderParcel(parcel)
        XCTAssertEqual(
            F50ResponseParser.parseQos(decoded),
            ParsedQos(qci: "8", downlink: "500Mbps", uplink: "100Mbps")
        )
    }

    func testRejectsTruncatedADBQosResponseWithoutUplink() {
        XCTAssertNil(
            F50ResponseParser.parseQos("+CGEQOSRDP: 1,8,0,0,0,0,500000,")
        )
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

    // MARK: - UFI-TOOLS 签名（用真实设备抓包验证过的向量，防止回归）

    func testKanoSignMatchesRealDeviceCapturedVector() {
        let key = F50Configuration.kanoSignKey
        // 真实抓包对：ts=1786770481007 的 goform 请求
        let msg = "minikanoGET/api/goform/goform_get_cmd_process1786770481007"
        XCTAssertEqual(
            F50ResponseParser.kanoSign(key: key, data: msg),
            "094188691724eb9bb7f31b50ae583584dccbf683262d8714a0b00d5c959fee21"
        )
        // 另一组抓包对：ts=1786770524826
        let msg2 = "minikanoGET/api/goform/goform_get_cmd_process1786770524826"
        XCTAssertEqual(
            F50ResponseParser.kanoSign(key: key, data: msg2),
            "b32d5a4da345cf392e97dbedc5dd861eed9f2621228c402ffca53898deaf8f0c"
        )
    }

    func testKanoSignHashesRawBytesNotHexText() {
        // 关键陷阱：若误对 HMAC 结果的 hex 文本做 SHA256，会得到不同的签名。
        // 真实设备要求对原始字节做哈希。
        let key = F50Configuration.kanoSignKey
        let msg = "minikanoGET/api/goform/goform_get_cmd_process1786770481007"
        let correct = F50ResponseParser.kanoSign(key: key, data: msg)
        XCTAssertEqual(correct, "094188691724eb9bb7f31b50ae583584dccbf683262d8714a0b00d5c959fee21")

        // 错误实现（对 hex 文本）产生的签名必须与正确实现不同
        var hmac = HMAC<Insecure.MD5>.authenticationCode(
            for: Data(msg.utf8),
            using: SymmetricKey(data: Data(key.utf8))
        )
        let hmacData = Data(hmac)
        let half = hmacData.count / 2
        func hexString(_ data: Data) -> String {
            data.map { String(format: "%02x", $0) }.joined()
        }
        let s1 = SHA256.hash(data: Data(hexString(hmacData.subdata(in: 0..<half)).utf8))
        let s2 = SHA256.hash(data: Data(hexString(hmacData.subdata(in: half..<hmacData.count)).utf8))
        var combined = Data()
        combined.append(contentsOf: s1)
        combined.append(contentsOf: s2)
        let wrong = SHA256.hash(data: combined).map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(wrong, correct, "对 hex 文本做哈希的实现不应通过")
    }

    func testSha256OfAdminIsLowercaseUFIToken() {
        // UFI authorization 头 = SHA256(口令) 小写 hex
        let digest = SHA256.hash(data: Data("admin".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918")
    }

    func testParseDoubleStripsSignalUnits() {
        XCTAssertEqual(F50ResponseParser.parseDouble("-85 dBm"), -85)
        XCTAssertEqual(F50ResponseParser.parseDouble("-8 dB"), -8)
        XCTAssertEqual(F50ResponseParser.parseDouble("14.5 dB"), 14.5)
        XCTAssertEqual(F50ResponseParser.parseDouble(NSNull()), 0)
    }

    func testFirstValidSignalValueSkipsNullAndZeroPlaceholdersInLeadingKeys() {
        // 设备在 NSA/4G 等状态下会把不适用的 nr_* 字段置为 null 或 "0"，
        // 真实值在 Z5g_* / 5g_* / lte_* 中 —— 不能被前置的无效值短路掉
        let dict: [String: Any] = [
            "nr_rsrp": NSNull(),
            "Z5g_rsrp": "-85",
            "nr_rsrq": "0",
            "5g_rsrq": "-9",
            "Nr_snr": NSNull(),
            "lte_snr": "12"
        ]
        XCTAssertEqual(
            F50ResponseParser.firstValidSignalValue(
                in: dict,
                keys: ["nr_rsrp", "Z5g_rsrp", "5g_rsrp", "lte_rsrp"]
            ), -85
        )
        XCTAssertEqual(
            F50ResponseParser.firstValidSignalValue(
                in: dict,
                keys: ["nr_rsrq", "Z5g_rsrq", "5g_rsrq", "lte_rsrq"]
            ), -9
        )
        XCTAssertEqual(
            F50ResponseParser.firstValidSignalValue(
                in: dict,
                keys: ["Nr_snr", "nr_snr", "Z5g_snr", "5g_snr", "lte_snr"]
            ), 12
        )
        XCTAssertNil(
            F50ResponseParser.firstValidSignalValue(
                in: dict,
                keys: ["Nr_snr", "5g_snr"]
            )
        )
    }

    func testFirstValidSignalValueIsCaseInsensitive() {
        // 部分固件返回 5G_rsrp / nr_snr 等大小写变体
        let dict: [String: Any] = [
            "5G_rsrp": "-90",
            "nr_snr": "14",
            "LTE_SNR": "8"
        ]
        XCTAssertEqual(
            F50ResponseParser.firstValidSignalValue(
                in: dict,
                keys: ["nr_rsrp", "Z5g_rsrp", "5g_rsrp", "lte_rsrp"]
            ), -90
        )
        XCTAssertEqual(
            F50ResponseParser.firstValidSignalValue(in: dict, keys: ["Nr_snr", "5g_snr", "lte_snr"]),
            14
        )
        XCTAssertEqual(
            F50ResponseParser.firstValidSignalValue(in: dict, keys: ["lte_snr"]),
            8
        )
    }

    func testFirstValidSignalValueParsesValuesWithUnits() {
        let dict: [String: Any] = [
            "nr_rsrp": "-85 dBm",
            "nr_rsrq": "-8 dB",
            "Nr_snr": "14 dB"
        ]
        XCTAssertEqual(F50ResponseParser.firstValidSignalValue(in: dict, keys: ["nr_rsrp"]), -85)
        XCTAssertEqual(F50ResponseParser.firstValidSignalValue(in: dict, keys: ["nr_rsrq"]), -8)
        XCTAssertEqual(F50ResponseParser.firstValidSignalValue(in: dict, keys: ["Nr_snr"]), 14)
    }

    func testFirstValidSignalValuePrefersNrOverLteWhenBothPresent() {
        // SA 模式下 nr_* 优先于 lte_*（与设备实际状态一致）
        let dict: [String: Any] = [
            "nr_rsrp": "-82",
            "lte_rsrp": "-100"
        ]
        XCTAssertEqual(
            F50ResponseParser.firstValidSignalValue(
                in: dict,
                keys: ["nr_rsrp", "Z5g_rsrp", "5g_rsrp", "lte_rsrp"]
            ), -82
        )
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
        if currentDay < resetDay {
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

    func testParsesCurrentBandsFromNetworkInformationDump() {
        // F50 不返回 nr5g_action_band 等字段，频段来自 network_information dump 的 Nr_bands
        let payload: [String: Any] = [
            "Nr_bands": 41,
            "Nr_fcn": 504990
        ]
        XCTAssertEqual(F50ResponseParser.parseCurrentBands(from: payload, networkType: "5G SA"), "n41")
        XCTAssertEqual(F50ResponseParser.parseCurrentBands(from: payload, networkType: "5G"), "n41")
        // Nr_bands 不适用于 NSA/LTE 的 LTE 主载波判断
        XCTAssertEqual(F50ResponseParser.parseCurrentBands(from: payload, networkType: "4G LTE"), "")
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

    func testCalculateLoginPasswordHashBothRawAndPreHashed() {
        let ld = "1234567890abcdef"
        let raw = "admin"
        let shaAdmin = "8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918"

        let hashFromRaw = F50ResponseParser.calculateLoginPasswordHash(tokenOrPassword: raw, ld: ld)
        let hashFromPreHashed = F50ResponseParser.calculateLoginPasswordHash(tokenOrPassword: shaAdmin, ld: ld)

        XCTAssertEqual(hashFromRaw, hashFromPreHashed)
        XCTAssertEqual(hashFromRaw.count, 64)
        XCTAssertEqual(hashFromRaw, hashFromRaw.uppercased())
    }

    func testFormatSMSTime() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 18
        components.hour = 12
        components.minute = 30
        components.second = 45
        guard let timeZone = TimeZone(secondsFromGMT: 8 * 3600),
              let date = calendar.date(from: components) else {
            XCTFail("Date construction failed")
            return
        }

        let formatted = F50ResponseParser.formatSMSTime(date: date, timeZone: timeZone)
        XCTAssertEqual(formatted, "26;08;18;12;30;45;+8")
    }

    func testBuildSMSRequestBodyEncodesProperly() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 18
        components.hour = 12
        components.minute = 30
        components.second = 45
        guard let timeZone = TimeZone(secondsFromGMT: 8 * 3600),
              let date = calendar.date(from: components) else {
            XCTFail("Date construction failed")
            return
        }

        let body = F50ResponseParser.buildSMSRequestBody(
            number: "+86 138-0013-8000",
            content: "测试 Hello",
            ad: "SAMPLEAD123",
            date: date,
            timeZone: timeZone
        )

        XCTAssertTrue(body.contains("goformId=SEND_SMS"))
        XCTAssertTrue(body.contains("isTest=false"))
        XCTAssertTrue(body.contains("notCallback=true"))
        XCTAssertTrue(body.contains("Number=%2B8613800138000"))
        XCTAssertTrue(body.contains("sms_time=26%3B08%3B18%3B12%3B30%3B45%3B%2B8"))
        XCTAssertTrue(body.contains("MessageBody=6d4b8bd5002000480065006c006c006f"))
        XCTAssertTrue(body.contains("ID=-1"))
        XCTAssertTrue(body.contains("encode_type=UNICODE"))
        XCTAssertTrue(body.contains("AD=SAMPLEAD123"))
    }

    // MARK: - Address & Endpoint Resolution Tests (Domain / Intranet Penetration Support)

    func testResolveEndpointsForLANIPDefault() {
        let (r1, u1) = F50Configuration.resolveEndpoints(from: "192.168.0.1")
        XCTAssertEqual(r1, "http://192.168.0.1")
        XCTAssertEqual(u1, "http://192.168.0.1:2333")

        let (r2, u2) = F50Configuration.resolveEndpoints(from: "http://192.168.0.1:2333")
        XCTAssertEqual(r2, "http://192.168.0.1")
        XCTAssertEqual(u2, "http://192.168.0.1:2333")

        let (r3, u3) = F50Configuration.resolveEndpoints(from: "")
        XCTAssertEqual(r3, "http://192.168.0.1")
        XCTAssertEqual(u3, "http://192.168.0.1:2333")
    }

    func testResolveEndpointsForDomainIgnores2333Port() {
        // 内网穿透域名：直接使用域名，不追加 :2333
        let (r1, u1) = F50Configuration.resolveEndpoints(from: "f50.example.com")
        XCTAssertEqual(r1, "http://f50.example.com")
        XCTAssertEqual(u1, "http://f50.example.com")

        let (r2, u2) = F50Configuration.resolveEndpoints(from: "https://f50.example.com")
        XCTAssertEqual(r2, "https://f50.example.com")
        XCTAssertEqual(u2, "https://f50.example.com")

        let (r3, u3) = F50Configuration.resolveEndpoints(from: "my-f50.frp.tunnel.xyz")
        XCTAssertEqual(r3, "http://my-f50.frp.tunnel.xyz")
        XCTAssertEqual(u3, "http://my-f50.frp.tunnel.xyz")
    }

    func testResolveEndpointsWithCustomPort() {
        let (r1, u1) = F50Configuration.resolveEndpoints(from: "f50.example.com:8443")
        XCTAssertEqual(r1, "http://f50.example.com:8443")
        XCTAssertEqual(u1, "http://f50.example.com:8443")

        let (r2, u2) = F50Configuration.resolveEndpoints(from: "https://f50.example.com:8443")
        XCTAssertEqual(r2, "https://f50.example.com:8443")
        XCTAssertEqual(u2, "https://f50.example.com:8443")

        let (r3, u3) = F50Configuration.resolveEndpoints(from: "192.168.0.1:8080")
        XCTAssertEqual(r3, "http://192.168.0.1:8080")
        XCTAssertEqual(u3, "http://192.168.0.1:8080")
    }

    func testIsValidAddressForIPAndDomain() {
        // Valid IP addresses
        XCTAssertTrue(F50Configuration.isValidAddress("192.168.0.1"))
        XCTAssertTrue(F50Configuration.isValidAddress("10.0.0.1"))
        XCTAssertTrue(F50Configuration.isValidAddress("192.168.0.1:2333"))
        XCTAssertTrue(F50Configuration.isValidAddress("http://192.168.0.1"))

        // Invalid IP addresses
        XCTAssertFalse(F50Configuration.isValidAddress("999.999.999.999"))
        XCTAssertFalse(F50Configuration.isValidAddress("192.168.0.300"))
        XCTAssertFalse(F50Configuration.isValidAddress("192.168.1"))

        // Valid Domain names
        XCTAssertTrue(F50Configuration.isValidAddress("f50.example.com"))
        XCTAssertTrue(F50Configuration.isValidAddress("https://f50.example.com"))
        XCTAssertTrue(F50Configuration.isValidAddress("my-f50.frp.tunnel.xyz:8443"))
        XCTAssertTrue(F50Configuration.isValidAddress("localhost"))

        // Invalid hostnames / strings
        XCTAssertFalse(F50Configuration.isValidAddress(""))
        XCTAssertFalse(F50Configuration.isValidAddress("   "))
        XCTAssertFalse(F50Configuration.isValidAddress("has space.com"))
        XCTAssertFalse(F50Configuration.isValidAddress("invalid/path"))
        XCTAssertFalse(F50Configuration.isValidAddress(".invalid.com"))
    }

    func testDisplayAddress() {
        XCTAssertEqual(F50Configuration.displayAddress(from: "http://192.168.0.1:2333"), "192.168.0.1")
        XCTAssertEqual(F50Configuration.displayAddress(from: "http://192.168.0.1"), "192.168.0.1")
        XCTAssertEqual(F50Configuration.displayAddress(from: "http://f50.example.com"), "f50.example.com")
        XCTAssertEqual(F50Configuration.displayAddress(from: "https://f50.example.com"), "https://f50.example.com")
        XCTAssertEqual(F50Configuration.displayAddress(from: "http://f50.example.com:8443"), "f50.example.com:8443")
    }

    func testNormalizeBaseURL() {
        XCTAssertEqual(F50Configuration.normalizeBaseURL("192.168.0.1"), "http://192.168.0.1:2333")
        XCTAssertEqual(F50Configuration.normalizeBaseURL("f50.example.com"), "http://f50.example.com")
        XCTAssertEqual(F50Configuration.normalizeBaseURL("https://f50.example.com"), "https://f50.example.com")
        XCTAssertEqual(F50Configuration.normalizeBaseURL("f50.example.com:8443"), "http://f50.example.com:8443")
    }

    func testNormalizesTemperatureAndUsageAliasesInUFIPayload() {
        let rawPayload: [String: Any] = [
            "soc_temp": 58500,
            "cpu_usage": 35.5,
            "mem_usage": 62.0,
            "qci_val": "9"
        ]
        let normalized = F50ResponseParser.normalizeUFIPayload(rawPayload)
        XCTAssertEqual(normalized["cpu_temp"] as? Double, 58.5)
        XCTAssertEqual(normalized["cpu_utility"] as? Double, 35.5)
        XCTAssertEqual(normalized["mem_utility"] as? Double, 62.0)
        XCTAssertEqual(normalized["qci"] as? String, "9")
    }

    func testParsesQosFromJSONAndNumericFormats() {
        // Direct JSON string
        let jsonQos = "{\"qci\": \"9\", \"qos_dl\": \"300Mbps\", \"qos_ul\": \"50Mbps\"}"
        let parsedJSON = F50ResponseParser.parseQos(jsonQos)
        XCTAssertEqual(parsedJSON?.qci, "9")
        XCTAssertEqual(parsedJSON?.downlink, "300Mbps")
        XCTAssertEqual(parsedJSON?.uplink, "50Mbps")

        // Pure numeric QCI
        let numQos = F50ResponseParser.parseQos("6")
        XCTAssertEqual(numQos?.qci, "6")
    }

    func testMergeHardwareMetricsFromRouterAndUFIAliases() {
        var status = F50Status()
        let payload: [String: Any] = [
            "internal_temperature": "54.2",
            "cpu_percent": "28.4",
            "mem_percent": "45.0",
            "qci": "9",
            "qos_dl": "500Mbps",
            "qos_ul": "100Mbps"
        ]
        status.mergeHardwareMetrics(from: payload)
        XCTAssertEqual(status.temperature, 54.2)
        XCTAssertEqual(status.cpuUsage, 28.4)
        XCTAssertEqual(status.memUsage, 45.0)
        XCTAssertEqual(status.qci, "9")
        XCTAssertEqual(status.qosDl, "500Mbps")
        XCTAssertEqual(status.qosUl, "100Mbps")
    }
}

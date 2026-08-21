import XCTest
@testable import F50Core

final class DeviceDiagnosticProbeTests: XCTestCase {
    func testSanitizesPasswordsAndTokensInJSON() {
        let rawJSON = """
        {
            "password": "SuperSecretPassword123",
            "token": "abcdef123456",
            "psk": "wifiPassword",
            "device_name": "TestRouter",
            "signal": -75
        }
        """

        let sanitized = DiagnosticSanitizer.sanitizeResponseSnippet(rawJSON, contentType: "application/json")
        XCTAssertFalse(sanitized.contains("SuperSecretPassword123"))
        XCTAssertFalse(sanitized.contains("abcdef123456"))
        XCTAssertFalse(sanitized.contains("wifiPassword"))
        XCTAssertTrue(sanitized.contains("******"))
        XCTAssertTrue(sanitized.contains("TestRouter"))
        XCTAssertTrue(sanitized.contains("-75"))
    }

    func testMasksIdentifiersInJSON() {
        let rawJSON = """
        {
            "imei": "861234567890123",
            "imsi": "460012345678901",
            "mac": "00:1A:2B:3C:4D:5E",
            "network_type": "5G SA"
        }
        """

        let sanitized = DiagnosticSanitizer.sanitizeResponseSnippet(rawJSON, contentType: "application/json")
        XCTAssertFalse(sanitized.contains("861234567890123"))
        XCTAssertFalse(sanitized.contains("460012345678901"))
        XCTAssertFalse(sanitized.contains("00:1A:2B:3C:4D:5E"))
        XCTAssertTrue(sanitized.contains("861****0123"))
        XCTAssertTrue(sanitized.contains("00:1A:**:**:4D:5E"))
        XCTAssertTrue(sanitized.contains("5G SA"))
    }

    func testSanitizesSMSMessages() {
        let rawJSON = """
        {
            "messages": [
                {"id": "1", "number": "13812345678", "content": "您的验证码是 987654，请勿泄露给他人。"}
            ]
        }
        """

        let sanitized = DiagnosticSanitizer.sanitizeResponseSnippet(rawJSON, contentType: "application/json")
        XCTAssertFalse(sanitized.contains("987654"))
        XCTAssertFalse(sanitized.contains("13812345678"))
        XCTAssertTrue(sanitized.contains("[已脱敏过滤]"))
        XCTAssertTrue(sanitized.contains("138****5678"))
    }

    func testGeneratesMarkdownReportWithCategoryAndAppState() {
        let endpoints = [
            EndpointProbeResult(
                name: "ZTE 状态接口",
                vendor: "中兴 (ZTE)",
                url: "http://192.168.0.1/goform/goform_get_cmd_process",
                method: "GET",
                statusCode: 200,
                statusText: "OK",
                latencyMs: 45,
                contentType: "application/json",
                serverHeader: "ZTE-Web-Server",
                responseSnippet: "{\"network_type\": \"5G SA\"}",
                isSuccess: true
            )
        ]

        let appState = AppStateSnapshot(
            isOnline: true,
            networkType: "5G SA",
            carrier: "中国联通",
            currentBands: "n78",
            signalBar: 4,
            rsrp: "-85",
            snr: "15",
            rsrq: "-9",
            temperature: 58.5
        )

        let report = DeviceDiagnosticReport(
            category: .missingData,
            appVersion: "2.1.1",
            osVersion: "macOS 14.5",
            deviceModel: "中兴 F30 Pro",
            userNotes: "无法读取芯片温度，但网络和流量正常",
            contact: "test_user@example.com",
            targetBaseURL: "192.168.0.1",
            appState: appState,
            endpoints: endpoints
        )

        XCTAssertEqual(report.successfulProbesCount, 1)

        let md = report.toMarkdown()
        XCTAssertTrue(md.contains("数据缺失 / 显示不全"))
        XCTAssertTrue(md.contains("中兴 F30 Pro"))
        XCTAssertTrue(md.contains("test_user@example.com"))
        XCTAssertTrue(md.contains("无法读取芯片温度"))
        XCTAssertTrue(md.contains("中国联通"))
        XCTAssertTrue(md.contains("n78"))
        XCTAssertTrue(md.contains("58.5℃"))
    }

    func testMaskAddressAndQueryString() {
        let masked = DiagnosticSanitizer.maskAddress("http://192.168.0.1/api?token=secret123&pass=admin&user=test")
        XCTAssertTrue(masked.contains("token=******"))
        XCTAssertTrue(masked.contains("pass=******"))
        XCTAssertTrue(masked.contains("user=test"))
    }
}

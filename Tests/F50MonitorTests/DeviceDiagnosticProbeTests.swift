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

    func testSanitizesNestedContentObjects() {
        let rawJSON = #"{"data":{"content":{"body":"短信正文不应泄漏","items":[{"content":"验证码 1234"}]}},"snr":"18"}"#
        let sanitized = DiagnosticSanitizer.sanitizeResponseSnippet(rawJSON, contentType: "application/json")
        XCTAssertFalse(sanitized.contains("短信正文不应泄漏"))
        XCTAssertFalse(sanitized.contains("验证码 1234"))
        XCTAssertTrue(sanitized.contains("[已脱敏过滤]"))
        XCTAssertTrue(sanitized.contains("18"))
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

    func testDoesNotMaskSNRMetric() {
        let rawJSON = """
        {
            "snr": "18.5",
            "rsnr": "22.0",
            "sn": "ZTE1234567890",
            "imei": "861234567890123"
        }
        """

        let sanitized = DiagnosticSanitizer.sanitizeResponseSnippet(rawJSON, contentType: "application/json")
        XCTAssertTrue(sanitized.contains("18.5"))
        XCTAssertTrue(sanitized.contains("22.0"))
        XCTAssertTrue(sanitized.contains("snr"))
        XCTAssertTrue(sanitized.contains("rsnr"))
        XCTAssertFalse(sanitized.contains("ZTE1234567890"))
        XCTAssertTrue(sanitized.contains("ZTE****7890"))
    }

    func testKanoSignatureConstructionIsDeterministic() {
        let data = "minikanoGET/api/baseDeviceInfo1234567890"
        let first = F50ResponseParser.kanoSign(key: F50Configuration.kanoSignKey, data: data)
        let second = F50ResponseParser.kanoSign(key: F50Configuration.kanoSignKey, data: data)
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
    }

    func testExtractsSanitizedQosEvidenceFromNestedATResponse() throws {
        let raw = #"{"result":{"content":"+CGEQOSRDP: 1,9,3,4,5,6,2000000,1000000\r\nOK"},"token":"do-not-store"}"#

        let evidence = try XCTUnwrap(DiagnosticSanitizer.sanitizedQosEvidence(raw))

        XCTAssertTrue(evidence.contains(#""qci" : "9""#))
        XCTAssertTrue(evidence.contains("2000Mbps"))
        XCTAssertTrue(evidence.contains("1000Mbps"))
        XCTAssertFalse(evidence.contains("do-not-store"))
        XCTAssertFalse(evidence.contains("CGEQOSRDP"))
    }

    func testDefaultProbesIncludeRouterAndSignedUFIQosDiagnostics() throws {
        let router = try XCTUnwrap(DeviceDiagnosticProbe.defaultProbeDefs.first { $0.name == "ZTE 签约状态" })
        XCTAssertTrue(router.path.contains("qci,ambr,dl_ambr,ul_ambr"))

        let ufi = try XCTUnwrap(DeviceDiagnosticProbe.defaultProbeDefs.first { $0.name == "UFI 签约状态 AT (:2333)" })
        XCTAssertEqual(ufi.portOverride, 2333)
        XCTAssertTrue(ufi.path.contains("CGEQOSRDP"))
        XCTAssertTrue(ufi.alwaysTryCandidateAuth)
        XCTAssertTrue(ufi.expectsQosPayload)
    }

    func testExtractsScriptCallSignatureWithoutValues() {
        let script = #"axios({url:"/cgi-bin/http.cgi",method:"post",data:{cmd:"network_info",password:"do-not-store",page:1}})"#

        let signatures = DiagnosticScriptAnalyzer.analyze(script, sourceScript: "/static/js/app.js")

        XCTAssertEqual(signatures.count, 1)
        XCTAssertEqual(signatures[0].endpoint, "/cgi-bin/http.cgi")
        XCTAssertEqual(signatures[0].sourceScript, "/static/js/app.js")
        XCTAssertEqual(signatures[0].methodCandidates, ["POST"])
        XCTAssertTrue(signatures[0].nearbyFieldNames.contains("cmd"))
        XCTAssertTrue(signatures[0].nearbyFieldNames.contains("password"))
        XCTAssertFalse(String(describing: signatures).contains("do-not-store"))
        XCTAssertFalse(String(describing: signatures).contains("network_info"))
    }

    func testReportSerializesStructuredScriptSignatures() throws {
        let report = DeviceDiagnosticReport(
            appVersion: "2.3.0",
            osVersion: "iOS",
            deviceModel: "ZLT M80",
            userNotes: "新设备适配",
            targetBaseURL: "192.168.0.1",
            scriptCallSignatures: [
                ScriptCallSignature(
                    endpoint: "/cgi-bin/http.cgi",
                    sourceScript: "/static/js/app.js",
                    methodCandidates: ["POST"],
                    nearbyFieldNames: ["cmd", "password"]
                )
            ]
        )

        let data = try XCTUnwrap(report.toJSONData())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let signatures = try XCTUnwrap(json["scriptCallSignatures"] as? [[String: Any]])
        XCTAssertEqual(signatures.first?["endpoint"] as? String, "/cgi-bin/http.cgi")
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("do-not-store"))
    }
}

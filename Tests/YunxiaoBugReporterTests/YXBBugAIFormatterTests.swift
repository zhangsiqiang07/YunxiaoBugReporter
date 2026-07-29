import XCTest
@testable import YunxiaoBugReporter

final class YXBBugAIFormatterTests: XCTestCase {
    func testRequestUsesServiceContractKeys() throws {
        let request = YXBBugAIGenerateRequest(
            description: "点击保存无响应",
            issueType: "function",
            severity: "major",
            frequency: "always",
            page: .init(name: "EditViewController", route: "pet/edit"),
            recentActions: ["进入编辑页", "点击保存"],
            environment: .init(
                appVersion: "1.0.0",
                build: "100",
                device: "iPhone17,1",
                osVersion: "18.0",
                network: "Wi-Fi"
            ),
            extra: ["登录状态": "已登录", "用户标识": "u_***1234"]
        )

        let data = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["issue_type"] as? String, "function")
        XCTAssertEqual(body["severity"] as? String, "major")
        XCTAssertEqual(body["recent_actions"] as? [String], ["进入编辑页", "点击保存"])
        XCTAssertEqual((body["environment"] as? [String: Any])?["app_version"] as? String, "1.0.0")
        XCTAssertEqual((body["extra"] as? [String: String])?["登录状态"], "已登录")
    }

    func testEndpointAppendsGeneratePath() throws {
        let endpoint = try YXBRemoteBugAIFormatter.makeEndpoint(serviceDomain: "https://bug-ai.example.com/gateway/")
        XCTAssertEqual(endpoint.absoluteString, "https://bug-ai.example.com/gateway/api/v1/bug-report/generate")
    }

    func testEndpointRejectsNonHTTPServiceDomain() {
        XCTAssertThrowsError(try YXBRemoteBugAIFormatter.makeEndpoint(serviceDomain: "ftp://bug-ai.example.com"))
    }
}

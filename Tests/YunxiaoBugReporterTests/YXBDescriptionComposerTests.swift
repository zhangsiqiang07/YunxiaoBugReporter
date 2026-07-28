import XCTest
@testable import YunxiaoBugReporter

final class YXBDescriptionComposerTests: XCTestCase {
    func testNetworkSectionIncludesBodiesWithoutHeadersAndUsesSafeFence() {
        let breadcrumbs = (0..<10).map { index in
            YXBNetworkBreadcrumb(
                method: "POST",
                path: "/v1/messages/\(index)?token=secret",
                requestHeaders: ["Authorization": "Bearer secret"],
                requestBody: "```text\nrequest body",
                statusCode: 200,
                durationMs: 100 + index,
                error: index == 0 ? "timeout\n# injected heading" : nil,
                responseHeaders: ["Set-Cookie": "secret"],
                responseBody: "```text\nresponse body"
            )
        }
        let context = YXBBugContext(
            appVersion: "1.0",
            build: "1",
            recentRequests: breadcrumbs
        )

        let description = YXBDescriptionComposer.compose(body: "## 问题描述\\n无法刷新", context: context)

        XCTAssertTrue(description.contains("- POST /v1/messages/0 · 200 · 100ms"))
        XCTAssertTrue(description.contains("错误：timeout # injected heading"))
        XCTAssertTrue(description.contains("- 其余 2 条网络请求未附带"))
        XCTAssertFalse(description.contains("Authorization"))
        XCTAssertFalse(description.contains("Set-Cookie"))
        XCTAssertTrue(description.contains("请求体\n````text\n```text\nrequest body\n````"))
        XCTAssertTrue(description.contains("响应体\n````text\n```text\nresponse body\n````"))
    }
}

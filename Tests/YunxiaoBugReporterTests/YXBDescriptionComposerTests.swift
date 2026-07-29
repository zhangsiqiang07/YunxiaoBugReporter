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

    func testUnclosedFencesInBodyAndEnvironmentDoNotConsumeFollowingSections() {
        let context = YXBBugContext(
            page: "DetailView\n```json\n{\"id\": 1}",
            recentRequests: [
                YXBNetworkBreadcrumb(
                    method: "GET",
                    path: "/v1/items",
                    requestHeaders: [:],
                    statusCode: 200,
                    durationMs: 20,
                    error: nil
                )
            ]
        )

        let description = YXBDescriptionComposer.compose(
            body: "问题详情：\n```swift\nlet enabled = false",
            context: context
        )

        XCTAssertTrue(description.contains("let enabled = false\n```\n\n## 环境信息"))
        XCTAssertTrue(description.contains("{\"id\": 1}\n```\n\n## 最近网络请求"))
    }

    func testEmptyJSONRequestBodyIsRenderedAsEmptyText() {
        let context = YXBBugContext(
            recentRequests: [
                YXBNetworkBreadcrumb(
                    method: "GET",
                    path: "/v1/messages/unread",
                    requestHeaders: [:],
                    requestBody: "{\n  \n}",
                    statusCode: 200,
                    durationMs: 244,
                    error: nil,
                    responseBody: "{\"success\": true}"
                )
            ]
        )

        let description = YXBDescriptionComposer.compose(body: "无法加载未读数", context: context)

        XCTAssertTrue(description.contains("请求体：空"))
        XCTAssertFalse(description.contains("请求体\n```text\n{\n  \n}"))
    }

    func testSupplementaryInfoIsIncludedAndCannotInjectMarkdownStructure() {
        let context = YXBBugContext(
            supplementaryInfo: [
                "登录状态": "已登录",
                "用户标识\n## 伪造标题": "u_123\n```swift\nsecret"
            ]
        )

        let description = YXBDescriptionComposer.compose(body: "无法保存", context: context)

        XCTAssertTrue(description.contains("- 登录状态：已登录"))
        XCTAssertTrue(description.contains("- 用户标识 ## 伪造标题：u_123 ```swift secret"))
        XCTAssertFalse(description.contains("\n## 伪造标题"))
    }
}

import XCTest
@testable import YunxiaoBugReporter

/// 覆盖：中心版/Region 版 URL 构造（1-4）、Token 头（5）、JSON 编码（6-7）、multipart（10-11）。
final class YXBEndpointAndRequestTests: XCTestCase {

    // MARK: - 1~4 URL 构造

    func testStandardQueryTypesURL() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.typesResponse, 200)])
        let service = YXBWorkitemService(config: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        _ = try await service.fetchBugTypes(token: "t")
        let recorded = mock.recordedRequests
        let url = try XCTUnwrap(recorded.first?.url?.absoluteString)
        XCTAssertTrue(url.contains("/oapi/v1/projex/organizations/org-1/projects/proj-1/workitemTypes"))
        XCTAssertTrue(url.contains("category=Bug"))
    }

    func testRegionQueryTypesURL() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.typesResponse, 200)])
        let config = YXBTestHelpers.makeConfig(edition: .region, organizationID: nil)
        let service = YXBWorkitemService(config: config, transport: mock)
        _ = try await service.fetchBugTypes(token: "t")
        let recorded = mock.recordedRequests
        let url = try XCTUnwrap(recorded.first?.url?.absoluteString)
        XCTAssertTrue(url.contains("/oapi/v1/projex/projects/proj-1/workitemTypes"))
        XCTAssertFalse(url.contains("/organizations/"))
    }

    func testStandardCreateWorkitemURL() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.createResponse, 200)])
        let service = YXBWorkitemService(config: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        _ = try await service.createWorkitem(report: makeReport(), workitemTypeID: "wt-1", token: "t")
        let recorded = mock.recordedRequests
        let url = try XCTUnwrap(recorded.first?.url?.absoluteString)
        XCTAssertTrue(url.contains("/oapi/v1/projex/organizations/org-1/workitems"))
    }

    func testRegionCreateWorkitemURL() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.createResponse, 200)])
        let config = YXBTestHelpers.makeConfig(edition: .region, organizationID: nil)
        let service = YXBWorkitemService(config: config, transport: mock)
        _ = try await service.createWorkitem(report: makeReport(), workitemTypeID: "wt-1", token: "t")
        let recorded = mock.recordedRequests
        let url = try XCTUnwrap(recorded.first?.url?.absoluteString)
        XCTAssertTrue(url.contains("/oapi/v1/projex/workitems"))
        XCTAssertFalse(url.contains("/organizations/"))
    }

    // MARK: - 5 Token 头

    func testTokenHeaderIsSet() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.typesResponse, 200)])
        let service = YXBWorkitemService(config: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        _ = try await service.fetchBugTypes(token: "secret-token-xyz")
        let recorded = mock.recordedRequests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-yunxiao-token"), "secret-token-xyz")
    }

    // MARK: - 6 JSON 编码

    func testCreateWorkitemJSONEncoding() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.createResponse, 200)])
        let config = YXBTestHelpers.makeConfig(edition: .standard)
        let service = YXBWorkitemService(config: config, transport: mock)
        let report = YXBBugReport(
            title: "崩溃问题",
            description: "点击按钮崩溃",
            format: .markdown,
            assignedTo: "assignee-9",
            customFields: ["priority": "P0"],
            labels: ["crash", "ios"]
        )
        _ = try await service.createWorkitem(report: report, workitemTypeID: "wt-1", token: "t")
        let recorded = mock.recordedRequests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let json = try XCTUnwrap(YXBTestHelpers.jsonBody(of: request))
        XCTAssertEqual(json["title"] as? String, "崩溃问题")
        XCTAssertEqual(json["description"] as? String, "点击按钮崩溃")
        XCTAssertEqual(json["workitemType"] as? String, "wt-1")
        XCTAssertEqual(json["assignedTo"] as? String, "assignee-9")
        XCTAssertEqual(json["descriptionFormat"] as? String, "MD")
        XCTAssertEqual(json["projectId"] as? String, "proj-1")
        XCTAssertEqual(json["organizationId"] as? String, "org-1")
        XCTAssertEqual(json["labels"] as? [String], ["crash", "ios"])
    }

    // MARK: - 7 customFieldValues 编码

    func testCustomFieldValuesEncoding() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.createResponse, 200)])
        let service = YXBWorkitemService(config: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        let report = YXBBugReport(
            title: "t",
            description: "d",
            customFields: ["fieldA": "valueA", "fieldB": "valueB"]
        )
        _ = try await service.createWorkitem(report: report, workitemTypeID: "wt-1", token: "t")
        let recorded = mock.recordedRequests
        let request = try XCTUnwrap(recorded.first)
        let json = try XCTUnwrap(YXBTestHelpers.jsonBody(of: request))
        let custom = try XCTUnwrap(json["customFieldValues"] as? [String: String])
        XCTAssertEqual(custom["fieldA"], "valueA")
        XCTAssertEqual(custom["fieldB"], "valueB")
    }

    // MARK: - 10 boundary 与 Content-Disposition

    func testMultipartBoundaryAndContentDisposition() throws {
        let attachment = YXBAttachment(data: Data("hello".utf8), fileName: "shot.png", mimeType: "image/png")
        let (body, boundary) = YXBMultipartBuilder.build(attachment: attachment)
        let text = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("--\(boundary)"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"shot.png\""))
        XCTAssertTrue(text.contains("--\(boundary)--"))
    }

    // MARK: - 11 文件名与 MIME + 请求头

    func testMultipartFileNameAndMIMEAndHeaders() throws {
        let attachment = YXBAttachment(data: Data("data".utf8), fileName: "log.txt", mimeType: "text/plain")
        let (body, boundary) = YXBMultipartBuilder.build(attachment: attachment)
        let text = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("filename=\"log.txt\""))
        XCTAssertTrue(text.contains("Content-Type: text/plain"))

        let request = try YXBRequestBuilder().buildMultipart(
            endpoint: .attachments(workitemId: "WI-1"),
            config: YXBTestHelpers.makeConfig(edition: .standard),
            token: "t",
            boundary: boundary,
            body: body
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=\(boundary)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), String(body.count))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-yunxiao-token"), "t")
    }

    private func makeReport() -> YXBBugReport {
        YXBBugReport(title: "示例", description: "描述")
    }
}

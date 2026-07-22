import XCTest
@testable import YunxiaoBugReporter

/// 覆盖完整提交链路：成功无附件(12)、全成功(13)、部分失败(14)、创建失败不上传(15)、
/// tokenProvider失败(16)、日志不泄露Token(17)、超大小(18)、顺序一致(19)、未配置(20)。
final class YunxiaoBugReporterSubmitTests: XCTestCase {

    // MARK: - 12 创建成功，无附件

    func testCreateSuccessNoAttachments() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.createResponse, 200)])
        let reporter = try YunxiaoBugReporter(configuration: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        let result = try await reporter.submit(YXBBugReport(title: "t", description: "d"))
        XCTAssertEqual(result.workitemID, "WI-123")
        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.successfulAttachments.isEmpty)
        XCTAssertTrue(result.failedAttachments.isEmpty)
        let count = mock.recordedRequests.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - 13 创建成功，附件全部成功

    func testCreateSuccessAllAttachmentsSucceed() async throws {
        let mock = YXBMockTransport(responses: [
            (YXBTestHelpers.createResponse, 200),
            (YXBTestHelpers.attachmentResponse(id: "ATT-1"), 200),
            (YXBTestHelpers.attachmentResponse(id: "ATT-2"), 200)
        ])
        let reporter = try YunxiaoBugReporter(configuration: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        let report = YXBBugReport(
            title: "t", description: "d",
            attachments: [
                YXBAttachment(data: Data("a".utf8), fileName: "a.png", mimeType: "image/png"),
                YXBAttachment(data: Data("b".utf8), fileName: "b.png", mimeType: "image/png")
            ]
        )
        let result = try await reporter.submit(report)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.successfulAttachments.count, 2)
        XCTAssertEqual(result.failedAttachments.count, 0)
        let count = mock.recordedRequests.count
        XCTAssertEqual(count, 3)
    }

    // MARK: - 14 创建成功，附件部分失败

    func testPartialAttachmentFailure() async throws {
        let mock = YXBMockTransport(handler: { req in
            let url = req.url?.absoluteString ?? ""
            if url.contains("/attachments") {
                if let body = req.httpBody, String(data: body, encoding: .utf8)?.contains("first.png") == true {
                    return (Data(#"{"message":"fail"}"#.utf8), 500)
                }
                return (YXBTestHelpers.attachmentResponse(id: "ATT-2"), 200)
            }
            return (YXBTestHelpers.createResponse, 200)
        })
        let reporter = try YunxiaoBugReporter(configuration: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        let report = YXBBugReport(
            title: "t", description: "d",
            attachments: [
                YXBAttachment(data: Data("a".utf8), fileName: "first.png", mimeType: "image/png"),
                YXBAttachment(data: Data("b".utf8), fileName: "second.png", mimeType: "image/png")
            ]
        )
        let result = try await reporter.submit(report)
        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertEqual(result.failedAttachments.count, 1)
        XCTAssertEqual(result.successfulAttachments.count, 1)
        XCTAssertEqual(result.failedAttachments.first?.fileName, "first.png")
        XCTAssertEqual(result.successfulAttachments.first?.fileName, "second.png")
    }

    // MARK: - 15 创建工作项失败，不上传附件

    func testCreationFailureDoesNotUploadAttachments() async throws {
        let mock = YXBMockTransport(handler: { req in
            if (req.url?.absoluteString ?? "").contains("/workitems") && req.httpMethod == "POST" {
                return (Data(#"{"message":"bad"}"#.utf8), 500)
            }
            return (YXBTestHelpers.attachmentResponse(id: "ATT"), 200)
        })
        let reporter = try YunxiaoBugReporter(configuration: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        let report = YXBBugReport(
            title: "t", description: "d",
            attachments: [YXBAttachment(data: Data("a".utf8), fileName: "a.png", mimeType: "image/png")]
        )
        do {
            _ = try await reporter.submit(report)
            XCTFail("应抛出错误")
        } catch {
            // 期望抛出
        }
        let recorded = mock.recordedRequests
        let urls = recorded.map { $0.url?.absoluteString ?? "" }
        XCTAssertEqual(urls.filter { $0.contains("/attachments") }.count, 0, "创建失败后不应上传附件")
        XCTAssertEqual(recorded.count, 1)
    }

    // MARK: - 16 tokenProvider 失败

    func testTokenProviderFailure() async throws {
        let config = YXBConfiguration(
            domain: "https://yx.example.com",
            edition: .standard,
            organizationID: "org-1",
            projectID: "proj-1",
            workitemTypeID: "wt-1",
            assignedTo: "user-1",
            tokenProvider: { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no token"]) }
        )
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.createResponse, 200)])
        let reporter = try YunxiaoBugReporter(configuration: config, transport: mock)
        do {
            _ = try await reporter.submit(YXBBugReport(title: "t", description: "d"))
            XCTFail("应抛出 tokenUnavailable")
        } catch YXBError.tokenUnavailable {
            // 期望
        } catch {
            XCTFail("错误类型不符: \(error)")
        }
        let count = mock.recordedRequests.count
        XCTAssertEqual(count, 0)
    }

    // MARK: - 17 日志不泄露 Token

    func testLoggingDoesNotLeakToken() async throws {
        let logger = YXBRecordingLogger()
        let config = YXBTestHelpers.makeConfig(edition: .standard, token: "super-secret-token-123", logger: logger)
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.createResponse, 200)])
        let reporter = try YunxiaoBugReporter(configuration: config, transport: mock)
        _ = try await reporter.submit(YXBBugReport(title: "t", description: "d"))
        XCTAssertFalse(logger.contains("super-secret-token-123"), "日志不应包含 Token")
    }

    // MARK: - 18 单附件超过大小限制

    func testAttachmentTooLarge() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.createResponse, 200)])
        let reporter = try YunxiaoBugReporter(configuration: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        let oversize = YXBAttachment(data: Data(count: 21 * 1024 * 1024), fileName: "big.png", mimeType: "image/png")
        let report = YXBBugReport(title: "t", description: "d", attachments: [oversize])
        // 大小限制属于报告级校验：超过限制的附件会让整个报告被拒绝，
        // 在创建工作项之前即抛错（不会创建 Bug，也不会发起网络请求）。
        // 运行时上传失败（网络/服务端）才会进入 partialSuccess 逻辑。
        do {
            _ = try await reporter.submit(report)
            XCTFail("超过大小限制的附件应导致提交抛错")
        } catch YXBError.attachmentTooLarge(let fileName, let limit) {
            XCTAssertEqual(fileName, "big.png")
            XCTAssertEqual(limit, 20 * 1024 * 1024)
        } catch {
            XCTFail("错误类型不符: \(error)")
        }
        let count = mock.recordedRequests.count
        XCTAssertEqual(count, 0)
    }

    // MARK: - 19 输入附件顺序与输出顺序一致

    func testInputOrderPreservedInOutput() async throws {
        let mock = YXBMockTransport(handler: { req in
            if (req.url?.absoluteString ?? "").contains("/attachments") {
                if let body = req.httpBody, String(data: body, encoding: .utf8)?.contains("first") == true {
                    return (Data(#"{"message":"x"}"#.utf8), 500)
                }
                return (YXBTestHelpers.attachmentResponse(id: "OK"), 200)
            }
            return (YXBTestHelpers.createResponse, 200)
        })
        let reporter = try YunxiaoBugReporter(configuration: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        let report = YXBBugReport(
            title: "t", description: "d",
            attachments: [
                YXBAttachment(data: Data("1".utf8), fileName: "first.png", mimeType: "image/png"),
                YXBAttachment(data: Data("2".utf8), fileName: "second.png", mimeType: "image/png"),
                YXBAttachment(data: Data("3".utf8), fileName: "third.png", mimeType: "image/png")
            ]
        )
        let result = try await reporter.submit(report)
        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertEqual(result.failedAttachments.first?.fileName, "first.png")
        XCTAssertEqual(result.successfulAttachments.map { $0.fileName }, ["second.png", "third.png"])
    }

    // MARK: - 20 未配置时提交报错

    func testNotConfiguredThrows() async {
        let reporter = YunxiaoBugReporter()
        do {
            _ = try await reporter.submit(YXBBugReport(title: "t", description: "d"))
            XCTFail("应抛出 notConfigured")
        } catch YXBError.notConfigured {
            // 期望
        } catch {
            XCTFail("错误类型不符: \(error)")
        }
    }
}

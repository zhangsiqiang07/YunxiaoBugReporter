import XCTest
@testable import YunxiaoBugReporter

/// 验证「带鉴权下载描述图片」：`downloadImage(at:)` 必须附加 `x-yunxiao-token` 头，
/// 并在收到 401 时清空 Token 缓存重试一次，其余错误直接透传。
final class YXBImageDownloadTests: XCTestCase {

    private var imageURL: URL {
        URL(string: "https://devops.aliyun.com/projex/api/workitem/file/url?fileIdentifier=abc")!
    }

    func testDownloadImageSendsTokenHeader() async throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // 伪 PNG 头
        let mock = YXBMockTransport(responses: [(imageData, 200)])
        let reporter = try YunxiaoBugReporter(
            configuration: YXBTestHelpers.makeConfig(edition: .standard),
            transport: mock
        )

        let result = try await reporter.downloadImage(at: imageURL)

        XCTAssertEqual(result, imageData, "应原样返回图片字节")
        guard let req = mock.recordedRequests.first(where: { $0.url == imageURL }) else {
            return XCTFail("未找到指向图片 URL 的请求")
        }
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-yunxiao-token"), "test-token",
                       "下载图片必须附加鉴权头，否则云效文件接口会拒绝")
    }

    func testDownloadImageRetriesOnceOn401() async throws {
        let imageData = Data([0x01, 0x02])
        // 第一次返回 401，第二次（重试）返回 200 + 图片数据。
        let mock = YXBMockTransport(responses: [(Data(), 401), (imageData, 200)])
        let reporter = try YunxiaoBugReporter(
            configuration: YXBTestHelpers.makeConfig(edition: .standard),
            transport: mock
        )

        let result = try await reporter.downloadImage(at: imageURL)

        XCTAssertEqual(result, imageData)
        let downloadRequests = mock.recordedRequests.filter { $0.url == imageURL }
        XCTAssertEqual(downloadRequests.count, 2, "401 后应清空 Token 缓存并重试一次")
    }

    func testDownloadImagePropagatesNon401Error() async {
        let mock = YXBMockTransport(responses: [(Data(), 404)])
        let reporter = try! YunxiaoBugReporter(
            configuration: YXBTestHelpers.makeConfig(edition: .standard),
            transport: mock
        )
        do {
            _ = try await reporter.downloadImage(at: imageURL)
            XCTFail("应抛出 404 错误")
        } catch let YXBError.httpError(statusCode: code, _) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("应为 YXBError.httpError，实际 \(error)")
        }
    }

    // MARK: - downloadWorkitemFile（控制台代理地址 → GetWorkitemFile → 临时地址）

    /// 验证：控制台代理地址先经 `GetWorkitemFile` 换临时地址（带 Token），再无 Token 下载字节。
    func testDownloadWorkitemFileResolvesTempURL() async throws {
        let workitemID = "WI-123"
        let fileId = "ead93cce1050d9c62cf398a9d7"
        let tempURLString = "https://yunxiao-temp-oss.example.com/files/pic.png?sign=xyz"
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        // 第一次请求：GetWorkitemFile（返回临时地址）；第二次：下载临时地址字节。
        let fileResponse = Data(#"{"url":"\#(tempURLString)"}"#.utf8)
        let mock = YXBMockTransport(responses: [(fileResponse, 200), (imageData, 200)])
        let reporter = try YunxiaoBugReporter(
            configuration: YXBTestHelpers.makeConfig(edition: .standard),
            transport: mock
        )

        let result = try await reporter.downloadWorkitemFile(fileIdentifier: fileId, workitemID: workitemID)

        XCTAssertEqual(result, imageData)
        let requests = mock.recordedRequests
        XCTAssertEqual(requests.count, 2, "应先请求 GetWorkitemFile，再下载临时地址")

        // 请求 1：GetWorkitemFile，路径含 workitems/{id}/files/{fileId}，且带 Token。
        let getFile = requests[0]
        XCTAssertTrue(getFile.url?.path.contains("/workitems/\(workitemID)/files/\(fileId)") == true,
                      "应请求 GetWorkitemFile 路径，实际 \(getFile.url?.path ?? "")")
        XCTAssertEqual(getFile.value(forHTTPHeaderField: "x-yunxiao-token"), "test-token")

        // 请求 2：临时地址，且不应携带 yunxiao Token（避免泄漏给第三方存储）。
        let download = requests[1]
        XCTAssertEqual(download.url?.absoluteString, tempURLString)
        XCTAssertNil(download.value(forHTTPHeaderField: "x-yunxiao-token"))
    }

    /// 验证：GetWorkitemFile 返回 401 时清空 Token 缓存并重试一次。
    func testDownloadWorkitemFileRetriesOn401() async throws {
        let fileId = "fid-1"
        let tempURLString = "https://oss.example.com/t.png?sign=1"
        let imageData = Data([0x01, 0x02])
        let fileResponse = Data(#"{"url":"\#(tempURLString)"}"#.utf8)

        // 401（GetWorkitemFile 首次）→ 200（GetWorkitemFile 重试）→ 200（下载临时地址）。
        let mock = YXBMockTransport(responses: [(Data(), 401), (fileResponse, 200), (imageData, 200)])
        let reporter = try YunxiaoBugReporter(
            configuration: YXBTestHelpers.makeConfig(edition: .standard),
            transport: mock
        )

        let result = try await reporter.downloadWorkitemFile(fileIdentifier: fileId, workitemID: "WI-9")
        XCTAssertEqual(result, imageData)

        let getFileRequests = mock.recordedRequests.filter {
            $0.url?.path.contains("/files/\(fileId)") == true
        }
        XCTAssertEqual(getFileRequests.count, 2, "GetWorkitemFile 收到 401 后应重试一次")
    }
}

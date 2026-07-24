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
}

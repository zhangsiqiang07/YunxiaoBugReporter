import Foundation

/// 基于 `URLSession` 的传输层实现。
///
/// 使用 `URLSession` 的 `async/await` API，不依赖任何第三方网络库。
/// 类本身不持有 Token；Token 由 `YXBRequestBuilder` 在请求头注入。
final class YXBHTTPClient: YXBTransport {
    private let session: URLSession

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = max(timeout, 60)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func send<T: Decodable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        let data = try await perform(request)
        do {
            return try YXBJSONCoder.decoder.decode(T.self, from: data)
        } catch {
            throw YXBError.decodingFailed(String(describing: error))
        }
    }

    func sendWithoutResponse(_ request: URLRequest) async throws {
        _ = try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw YXBError.underlying(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw YXBError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let parsed = YXBErrorParser.parse(data: data, statusCode: http.statusCode, response: http)
            throw YXBError.httpError(statusCode: http.statusCode, message: parsed.message)
        }

        return data
    }
}

// `URLSession` 在部分 SDK 版本中未被标记为 `Sendable`；此处以 unchecked 声明，
// 因为 `URLSession` 实例本身可被安全并发使用。
extension YXBHTTPClient: @unchecked Sendable {}

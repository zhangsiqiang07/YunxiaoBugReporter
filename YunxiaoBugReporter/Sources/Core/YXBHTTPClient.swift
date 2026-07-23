import Foundation
import os

/// 基于 `URLSession` 的传输层实现。
///
/// 使用 `URLSession` 的 `async/await` API，不依赖任何第三方网络库。
/// 类本身不持有 Token；Token 由 `YXBRequestBuilder` 在请求头注入。
///
/// 该实现是**所有 HTTP 请求的唯一出口**，因此在此统一记录每个请求的日志：
/// 请求方法 / URL / 脱敏后的请求头 / body 字节数，以及响应状态码 / 耗时 / 响应字节数，
/// 失败时记录错误。Token 头（`x-yunxiao-token`）一律以 `<redacted>` 输出，不会泄露。
final class YXBHTTPClient: YXBTransport {
    private let session: URLSession
    private let logger: (any YXBLogger)?

    init(timeout: TimeInterval, logger: (any YXBLogger)? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = max(timeout, 60)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        self.logger = logger
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
        let started = Date()
        logger?.log(level: .info, message: "[YunxiaoBugReporter] → \(describeRequest(request))")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let duration = Date().timeIntervalSince(started)
            logger?.log(
                level: .error,
                message: "[YunxiaoBugReporter] ✗ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<unknown>") " +
                        "失败（耗时 \(String(format: "%.2f", duration))s）：\(String(describing: error))"
            )
            throw YXBError.underlying(String(describing: error))
        }

        let duration = Date().timeIntervalSince(started)
        guard let http = response as? HTTPURLResponse else {
            logger?.log(
                level: .error,
                message: "[YunxiaoBugReporter] ✗ 收到非 HTTP 响应（耗时 \(String(format: "%.2f", duration))s）"
            )
            throw YXBError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            logger?.log(
                level: .info,
                message: "[YunxiaoBugReporter] ← \(http.statusCode) \(request.url?.absoluteString ?? "") " +
                        "（耗时 \(String(format: "%.2f", duration))s，\(data.count) bytes）"
            )
            return data
        }

        let parsed = YXBErrorParser.parse(data: data, statusCode: http.statusCode, response: http)
        logger?.log(
            level: .error,
            message: "[YunxiaoBugReporter] ← \(http.statusCode) \(request.url?.absoluteString ?? "") " +
                    "（耗时 \(String(format: "%.2f", duration))s）：\(parsed.message)"
        )
        throw YXBError.httpError(statusCode: http.statusCode, message: parsed.message)
    }

    /// 构造请求的可读描述，Token 头脱敏。
    private func describeRequest(_ request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "<unknown>"
        var headerStrs: [String] = []
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            if key.lowercased() == "x-yunxiao-token" {
                headerStrs.append("\(key): <redacted>")
            } else {
                headerStrs.append("\(key): \(value)")
            }
        }
        var parts = ["\(method) \(url)"]
        if !headerStrs.isEmpty {
            parts.append("headers={ \(headerStrs.joined(separator: ", ")) }")
        }
        if let body = request.httpBody {
            parts.append("body=\(body.count) bytes")
        }
        return parts.joined(separator: " ")
    }
}

// `URLSession` 在部分 SDK 版本中未被标记为 `Sendable`；此处以 unchecked 声明，
// 因为 `URLSession` 实例本身可被安全并发使用。
extension YXBHTTPClient: @unchecked Sendable {}

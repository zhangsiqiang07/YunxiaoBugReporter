import Foundation

/// 云效错误响应解析。
///
/// 尝试从响应体提取 `message` / `code` / `requestId` 等字段；从响应头提取 `x-request-id`。
/// 解析过程完全基于服务端返回内容，**不会**接触 Token 或任何客户端敏感信息。
enum YXBErrorParser {
    /// 解析后的错误信息（全部为 `Sendable` 字符串）。
    struct ParsedError: Sendable {
        let message: String?
        let code: String?
        let requestId: String?
    }

    static func parse(data: Data, statusCode: Int, response: HTTPURLResponse? = nil) -> ParsedError {
        var message: String?
        var code: String?
        var requestId: String?

        if let response = response {
            requestId = response.value(forHTTPHeaderField: "x-request-id")
                ?? response.value(forHTTPHeaderField: "X-Request-ID")
        }

        if !data.isEmpty,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            message = string(in: object, keys: ["message", "errorMessage", "error", "msg"])
            code = string(in: object, keys: ["code", "errorCode", "error_code"])
            if requestId == nil {
                requestId = string(in: object, keys: ["requestId", "request_id", "requestID"])
            }
        }

        return ParsedError(message: message, code: code, requestId: requestId)
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let value = object[key] {
                return String(describing: value)
            }
        }
        return nil
    }
}

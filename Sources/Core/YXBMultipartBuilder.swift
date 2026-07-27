import Foundation

/// multipart/form-data 构造器。
///
/// 严格按照 RFC 7578 生成：
/// - 随机 boundary；
/// - 正确的 CRLF（`\r\n`）；
/// - `Content-Disposition` 中 `name` 固定为 `file`，并带 `filename`；
/// - 带 `Content-Type`；
/// - 支持任意 `Data`。
enum YXBMultipartBuilder {
    /// 生成随机 boundary。
    static func randomBoundary() -> String {
        let alphanumerics = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var result = "----YunxiaoBugReporterBoundary"
        for _ in 0..<24 {
            let offset = Int(arc4random_uniform(UInt32(alphanumerics.utf8.count)))
            let index = alphanumerics.index(alphanumerics.startIndex, offsetBy: offset)
            result.append(alphanumerics[index])
        }
        return result
    }

    /// 构造 multipart 请求体。
    /// - Returns: `(body, boundary)`。调用方据此设置 `Content-Type` 与 `Content-Length`。
    static func build(attachment: YXBAttachment) -> (body: Data, boundary: String) {
        let boundary = randomBoundary()
        var body = Data()
        let crlf = "\r\n"

        body.append("--\(boundary)\(crlf)")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(attachment.fileName)\"\(crlf)")
        body.append("Content-Type: \(attachment.mimeType)\(crlf)\(crlf)")
        body.append(attachment.data)
        body.append("\(crlf)")
        body.append("--\(boundary)--\(crlf)")

        return (body, boundary)
    }
}

extension Data {
    /// 追加字符串（默认 UTF-8）。
    mutating func append(_ string: String, encoding: String.Encoding = .utf8) {
        if let data = string.data(using: encoding) {
            append(data)
        }
    }
}

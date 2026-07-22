import Foundation

/// 传输层协议。HTTP 实现与 Mock 实现均遵循该协议，方便在测试中注入 Mock Transport。
///
/// 协议标记为 `Sendable`，因此其所有实现（如基于 actor 的 Mock）都可安全跨并发使用。
public protocol YXBTransport: Sendable {
    /// 发送请求并解码为 `T`。
    func send<T: Decodable>(
        _ request: URLRequest,
        responseType: T.Type
    ) async throws -> T

    /// 发送请求且不解码响应体（用于不需要返回体的请求）。
    func sendWithoutResponse(
        _ request: URLRequest
    ) async throws
}

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

    /// 下载二进制数据（如工作项描述中的图片），不解码为模型，直接返回原始 `Data`。
    ///
    /// 复用与 `send` 相同的唯一 HTTP 出口（日志、错误解析、状态码校验均一致），
    /// 便于在需要自定义头（如 `x-yunxiao-token`）下载资源时使用。
    func download(
        _ request: URLRequest
    ) async throws -> Data
}

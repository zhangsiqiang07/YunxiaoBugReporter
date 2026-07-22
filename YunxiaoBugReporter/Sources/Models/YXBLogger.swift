import Foundation

/// 可选的日志协议。宿主可注入自己的日志实现（如接入自有上报系统）。
/// 协议标记为 `Sendable`，可在并发上下文中安全使用。
public protocol YXBLogger: Sendable {
    /// 输出一条日志。
    /// - Parameters:
    ///   - level: 日志级别。
    ///   - message: 日志内容。SDK 保证不会在此处输出 Token、完整附件二进制或敏感请求体。
    func log(level: YXBLogLevel, message: String)
}

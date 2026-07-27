import Foundation

/// SDK 结构化错误。
///
/// 为满足 Swift 严格并发（`Sendable`）要求，原本携带 `Error` 的关联值在此统一改为 `String`
/// （保存原始错误的 `localizedDescription` 或自定义说明）。语义与需求保持一致：
/// Token 不可用、解码失败、创建工作项失败、底层错误均带有可读原因。
public enum YXBError: Error, Sendable {
    /// SDK 尚未配置（未调用 `configure(_:)` 或未通过初始化器传入配置）。
    case notConfigured
    /// 配置校验失败，附带原因。
    case invalidConfiguration(String)
    /// Bug 报告校验失败，附带原因。
    case invalidReport(String)
    /// 获取 Token 失败，附带原因（不含 Token 本身）。
    case tokenUnavailable(String)
    /// 响应不是合法的 HTTP 响应。
    case invalidResponse
    /// HTTP 非 2xx。保存状态码与（已脱敏的）服务端消息。
    case httpError(statusCode: Int, message: String?)
    /// 响应解码失败，附带原因。
    case decodingFailed(String)
    /// 未找到可用的 Bug 工作项类型。
    case workitemTypeNotFound
    /// 创建工作项失败，附带原因。
    case workitemCreationFailed(String)
    /// 单个附件超过大小限制。
    case attachmentTooLarge(fileName: String, limit: Int)
    /// 其他底层错误，附带原因。
    case underlying(String)
}

extension YXBError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "YunxiaoBugReporter 尚未配置，请先调用 configure(_:) 或在初始化时传入 configuration。"
        case .invalidConfiguration(let message):
            return "配置无效: \(message)"
        case .invalidReport(let message):
            return "Bug 报告无效: \(message)"
        case .tokenUnavailable(let message):
            return "获取 Token 失败: \(message)"
        case .invalidResponse:
            return "响应无效：未收到合法 HTTP 响应。"
        case .httpError(let statusCode, let message):
            return "HTTP 错误 \(statusCode): \(message ?? "无服务端错误信息")"
        case .decodingFailed(let message):
            return "响应解码失败: \(message)"
        case .workitemTypeNotFound:
            return "未找到可用的 Bug 工作项类型（没有启用中的 Bug 类型）。"
        case .workitemCreationFailed(let message):
            return "创建工作项失败: \(message)"
        case .attachmentTooLarge(let fileName, let limit):
            return "附件 \"\(fileName)\" 超过大小限制（上限 \(limit) 字节）。"
        case .underlying(let message):
            return "未知错误: \(message)"
        }
    }
}

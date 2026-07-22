import Foundation

/// Bug 描述格式。云效工作项接口对描述格式的枚举值可能与具体租户配置相关，
/// 首期提供纯文本与 Markdown 两种常用取值，可按需扩展。
public enum YXBDescriptionFormat: String, Sendable, Codable {
    /// 纯文本。
    case plainText = "TEXT"
    /// Markdown。
    case markdown = "MD"
}

import Foundation

/// 描述嵌入器：把已上传成功的图片片段拼接到工作项描述中，
/// 使图片直接显示在工作项描述里（云效 Web 端与详情页均可渲染），而非仅作为独立附件。
///
/// 云效 `CreateWorkitemAttachment` 会在响应里给出 `embedHtml`（RICHTEXT 模式）、
/// `embedMarkdown`（MARKDOWN 模式）与永久不过期的 `embedUrl`，本工具按描述格式择优选用。
enum YXBDescriptionEmbedder {
    /// 按描述格式从单个附件结果里挑出合适的图片片段；非成功附件返回 nil。
    static func snippet(for result: YXBAttachmentResult, format: YXBDescriptionFormat) -> String? {
        guard result.success else { return nil }
        switch format {
        case .markdown:
            if let md = result.embedMarkdown, !md.isEmpty { return md }
            return result.embedURL.map { "![image](\($0))" }
        case .plainText:
            if let html = result.embedHTML, !html.isEmpty { return html }
            return result.embedURL.map { "<img src=\"\($0)\" />" }
        }
    }

    /// 把成功附件的图片片段追加到原始描述之后。
    /// 没有任何可嵌入片段时返回 nil（调用方据此跳过描述更新）。
    static func embed(
        attachments: [YXBAttachmentResult],
        format: YXBDescriptionFormat,
        into original: String
    ) -> String? {
        let snippets = attachments.compactMap { snippet(for: $0, format: format) }
            .filter { !$0.isEmpty }
        guard !snippets.isEmpty else { return nil }
        return ([original] + snippets).joined(separator: "\n")
    }
}

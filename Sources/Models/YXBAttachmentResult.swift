import Foundation

/// 单个附件的上传结果。
public struct YXBAttachmentResult: Sendable {
    /// 文件名。
    public let fileName: String
    /// 是否上传成功。
    public let success: Bool
    /// 成功时返回的服务端附件 ID。
    public let attachmentID: String?
    /// 成功且为图片时，RICHTEXT 模式可嵌入描述的 `<img>` 片段。
    public let embedHTML: String?
    /// 成功且为图片时，MARKDOWN 模式可嵌入描述的图片片段。
    public let embedMarkdown: String?
    /// 成功且为图片时，永久代理地址（不会过期），可手动拼成 `<img>` / `![]()`。
    public let embedURL: String?
    /// 失败时的错误原因（不含 Token）。
    public let error: YXBError?

    init(
        fileName: String,
        success: Bool,
        attachmentID: String? = nil,
        embedHTML: String? = nil,
        embedMarkdown: String? = nil,
        embedURL: String? = nil,
        error: YXBError? = nil
    ) {
        self.fileName = fileName
        self.success = success
        self.attachmentID = attachmentID
        self.embedHTML = embedHTML
        self.embedMarkdown = embedMarkdown
        self.embedURL = embedURL
        self.error = error
    }
}

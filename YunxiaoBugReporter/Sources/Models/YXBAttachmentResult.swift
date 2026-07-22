import Foundation

/// 单个附件的上传结果。
public struct YXBAttachmentResult: Sendable {
    /// 文件名。
    public let fileName: String
    /// 是否上传成功。
    public let success: Bool
    /// 成功时返回的服务端附件 ID。
    public let attachmentID: String?
    /// 失败时的错误原因（不含 Token）。
    public let error: YXBError?

    init(fileName: String, success: Bool, attachmentID: String? = nil, error: YXBError? = nil) {
        self.fileName = fileName
        self.success = success
        self.attachmentID = attachmentID
        self.error = error
    }
}

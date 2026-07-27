import Foundation

/// 一次完整提交的结果。只要工作项创建成功，即使部分附件失败也会返回该结果，而非抛错。
public struct YXBSubmitResult: Sendable {
    /// 创建成功的工作项 ID。
    public let workitemID: String
    /// 整体状态（success / partialSuccess）。
    public let status: YXBSubmitStatus
    /// 上传成功的附件结果。
    public let successfulAttachments: [YXBAttachmentResult]
    /// 上传失败的附件结果。
    public let failedAttachments: [YXBAttachmentResult]

    init(
        workitemID: String,
        status: YXBSubmitStatus,
        successfulAttachments: [YXBAttachmentResult],
        failedAttachments: [YXBAttachmentResult]
    ) {
        self.workitemID = workitemID
        self.status = status
        self.successfulAttachments = successfulAttachments
        self.failedAttachments = failedAttachments
    }
}

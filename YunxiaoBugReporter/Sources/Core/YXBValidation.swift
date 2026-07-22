import Foundation

/// 配置与报告校验。集中实现需求中的校验规则。
enum YXBValidation {
    /// 校验配置。不通过时抛出 `YXBError.invalidConfiguration`。
    static func validateConfiguration(_ config: YXBConfiguration) throws {
        guard let url = URL(string: config.domain),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https") else {
            throw YXBError.invalidConfiguration("domain 必须是 http 或 https URL: \(config.domain)")
        }
        if config.edition == .standard, (config.organizationID ?? "").isEmpty {
            throw YXBError.invalidConfiguration("中心版(standard)必须提供 organizationID。")
        }
        guard !config.projectID.isEmpty else {
            throw YXBError.invalidConfiguration("projectID 不得为空。")
        }
        guard !config.assignedTo.isEmpty else {
            throw YXBError.invalidConfiguration("assignedTo 不得为空。")
        }
        guard config.timeout > 0 else {
            throw YXBError.invalidConfiguration("timeout 必须大于 0。")
        }
        guard (1...4).contains(config.maximumConcurrentUploads) else {
            throw YXBError.invalidConfiguration("maximumConcurrentUploads 必须在 1...4 范围内，当前为 \(config.maximumConcurrentUploads)。")
        }
    }

    /// 校验报告。不通过时抛出 `YXBError.invalidReport` 或 `YXBError.attachmentTooLarge`。
    static func validateReport(_ report: YXBBugReport) throws {
        let title = report.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw YXBError.invalidReport("title 去除空白后不得为空。")
        }
        for attachment in report.attachments {
            try validateAttachment(attachment, maxBytes: YXBConstants.maxAttachmentBytes)
        }
    }

    /// 校验单个附件。
    static func validateAttachment(_ attachment: YXBAttachment, maxBytes: Int) throws {
        guard !attachment.data.isEmpty else {
            throw YXBError.invalidReport("附件 data 不得为空（fileName=\(attachment.fileName)）。")
        }
        guard !attachment.fileName.isEmpty else {
            throw YXBError.invalidReport("fileName 不得为空。")
        }
        guard !attachment.mimeType.isEmpty else {
            throw YXBError.invalidReport("mimeType 不得为空（fileName=\(attachment.fileName)）。")
        }
        guard attachment.data.count <= maxBytes else {
            throw YXBError.attachmentTooLarge(fileName: attachment.fileName, limit: maxBytes)
        }
    }
}

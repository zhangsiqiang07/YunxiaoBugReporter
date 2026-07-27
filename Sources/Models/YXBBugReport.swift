import Foundation

/// 一次 Bug 上报的内容描述。
public struct YXBBugReport: Sendable {
    /// Bug 标题。去除空白后不得为空。
    public var title: String

    /// Bug 描述正文。
    public var description: String

    /// 描述格式（纯文本 / Markdown）。
    public var format: YXBDescriptionFormat

    /// 覆盖配置中的负责人；为空时使用配置里的 `assignedTo`。
    public var assignedTo: String?

    /// 自定义字段键值对，编码为请求体的 `customFieldValues`。
    public var customFields: [String: String]

    /// 标签列表。
    public var labels: [String]

    /// 附件列表。
    public var attachments: [YXBAttachment]

    public init(
        title: String,
        description: String,
        format: YXBDescriptionFormat = .plainText,
        assignedTo: String? = nil,
        customFields: [String: String] = [:],
        labels: [String] = [],
        attachments: [YXBAttachment] = []
    ) {
        self.title = title
        self.description = description
        self.format = format
        self.assignedTo = assignedTo
        self.customFields = customFields
        self.labels = labels
        self.attachments = attachments
    }
}

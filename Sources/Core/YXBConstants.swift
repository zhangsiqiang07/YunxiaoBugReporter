/// 内部常量集合。所有数值集中管理，便于后续调整与外部说明。
enum YXBConstants {
    /// 单个附件默认大小上限：20 MB（首期固定值）。
    static let maxAttachmentBytes = 20 * 1024 * 1024

    /// 附件上传默认并发数。
    static let defaultMaximumConcurrentUploads = 2

    /// 附件上传并发数硬上限（与配置校验 1...4 对齐）。
    static let maxConcurrentUploadsCap = 4
}

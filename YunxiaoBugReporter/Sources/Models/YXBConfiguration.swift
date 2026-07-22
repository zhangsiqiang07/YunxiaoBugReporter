import Foundation

/// SDK 配置。所有字段均为公开可配置项。
public struct YXBConfiguration: Sendable {
    /// 云效版本。
    public enum Edition: Sendable {
        /// 中心版：URL 路径包含 `/organizations/{organizationId}`。
        case standard
        /// Region 版：URL 路径不含 organization 段。
        case region
    }

    /// 云效服务域名，必须为 http/https URL（如 `https://yunxiao.example.com`）。
    public var domain: String

    /// 版本（中心版 / Region 版）。
    public var edition: Edition

    /// 组织 ID。中心版必填；Region 版忽略。
    public var organizationID: String?

    /// 项目 ID。必填。
    public var projectID: String

    /// 显式指定的工作项类型 ID。若为空，SDK 会自动选择 Bug 类型。
    public var workitemTypeID: String?

    /// 负责人用户 ID（Assignee）。必填。
    public var assignedTo: String

    /// 异步 Token 提供闭包。SDK 不持久化 Token，每次需要时调用。
    /// 失败时抛出，SDK 会转换为 `YXBError.tokenUnavailable`。
    public var tokenProvider: @Sendable () async throws -> String

    /// 请求超时时间（秒）。必须大于 0。
    public var timeout: TimeInterval

    /// 可选日志器。
    public var logger: (any YXBLogger)?

    /// 附件上传并发数，范围 1...4，默认 2。
    public var maximumConcurrentUploads: Int

    public init(
        domain: String,
        edition: Edition,
        organizationID: String?,
        projectID: String,
        workitemTypeID: String? = nil,
        assignedTo: String,
        tokenProvider: @escaping @Sendable () async throws -> String,
        timeout: TimeInterval = 30,
        logger: (any YXBLogger)? = nil,
        maximumConcurrentUploads: Int = 2
    ) {
        self.domain = domain
        self.edition = edition
        self.organizationID = organizationID
        self.projectID = projectID
        self.workitemTypeID = workitemTypeID
        self.assignedTo = assignedTo
        self.tokenProvider = tokenProvider
        self.timeout = timeout
        self.logger = logger
        self.maximumConcurrentUploads = maximumConcurrentUploads
    }
}

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
    ///
    /// 当 `cache` 非 `nil` 且 `tokenCacheTTL > 0` 时，Token 会被写入缓存，
    /// 在 TTL 内重复提交直接命中缓存、不再调用本闭包。
    public var tokenProvider: @Sendable () async throws -> String

    /// 请求超时时间（秒）。必须大于 0。
    public var timeout: TimeInterval

    /// 可选日志器。
    ///
    /// 为 `nil` 时，SDK 自动使用内置的 `YXBOSLogger`（基于 `os.log`），
    /// 即**所有请求默认都会记录日志**。传入 `YXBNoOpLogger()` 可显式关闭日志。
    public var logger: (any YXBLogger)?

    /// 附件上传并发数，范围 1...4，默认 2。
    public var maximumConcurrentUploads: Int

    /// 结果缓存后端。`nil` 表示关闭缓存（默认）。
    ///
    /// 启用后，SDK 会缓存「自动解析出的工作项类型」与「Token」：
    /// - 工作项类型按 `(edition, organizationID, projectID)` 作为键，TTL 由 `workitemTypeCacheTTL` 控制；
    /// - Token 以固定键缓存，TTL 由 `tokenCacheTTL` 控制。
    ///
    /// 缓存读取/写入失败均静默降级，不影响主流程。
    public var cache: (any YXBCache)?

    /// 工作项类型缓存存活时间（秒）。默认 3600（1 小时）。仅当 `cache` 非 `nil` 时生效。
    public var workitemTypeCacheTTL: TimeInterval

    /// Token 缓存存活时间（秒）。默认 300（5 分钟）。`<= 0` 表示不缓存 Token。仅当 `cache` 非 `nil` 时生效。
    ///
    /// ⚠️ 若缓存后端为 `YXBUserDefaultsCache`，Token 将以明文落盘，存在泄露风险，建议改用 `YXBInMemoryCache`。
    public var tokenCacheTTL: TimeInterval

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
        maximumConcurrentUploads: Int = 2,
        cache: (any YXBCache)? = nil,
        workitemTypeCacheTTL: TimeInterval = 3600,
        tokenCacheTTL: TimeInterval = 300
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
        self.cache = cache
        self.workitemTypeCacheTTL = workitemTypeCacheTTL
        self.tokenCacheTTL = tokenCacheTTL
    }
}

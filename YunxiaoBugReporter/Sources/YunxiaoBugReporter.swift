import Foundation

/// `YunxiaoBugReporter` 是 SDK 的公开门面。
///
/// 使用方式：
/// ```swift
/// let reporter = YunxiaoBugReporter()
/// try reporter.configure(configuration)
/// let result = try await reporter.submit(report)
/// ```
///
/// 设计要点：
/// - SDK 不持久化 Token；每次提交通过 `YXBConfiguration.tokenProvider` 获取；
/// - 配置 `YXBConfiguration.cache` 后可缓存「自动解析的工作项类型」与「Token」，
///   减少云效 API 与 `tokenProvider` 的重复调用；缓存读取失败静默降级走网络；
/// - 只要工作项创建成功，即使部分附件失败也返回 `YXBSubmitResult`（状态为 `.partialSuccess`），
///   而不是抛错；
/// - 工作项创建失败或配置/报告不合法时才会 `throw`。
public final class YunxiaoBugReporter {
    private var config: YXBConfiguration?
    private var transport: (any YXBTransport)?
    private var workitemService: YXBWorkitemService?
    private var attachmentService: YXBAttachmentService?

    /// 创建未配置的实例。需先调用 `configure(_:)` 才能提交。
    public init() {}

    /// 使用配置初始化（配置仍会被校验，不合法会抛错）。
    /// - Parameters:
    ///   - configuration: 配置。
    ///   - transport: 可选注入的传输层（测试用）。生产环境不传，使用默认 `URLSession` 实现。
    internal init(configuration: YXBConfiguration, transport: (any YXBTransport)? = nil) throws {
        try YXBValidation.validateConfiguration(configuration)
        let resolvedTransport = transport ?? YXBHTTPClient(
            timeout: configuration.timeout,
            logger: configuration.logger ?? YXBOSLogger.shared
        )
        apply(configuration: configuration, transport: resolvedTransport)
    }

    /// 配置 SDK。重复调用会覆盖之前的配置。
    public func configure(_ configuration: YXBConfiguration) throws {
        try YXBValidation.validateConfiguration(configuration)
        let client = YXBHTTPClient(
            timeout: configuration.timeout,
            logger: configuration.logger ?? YXBOSLogger.shared
        )
        apply(configuration: configuration, transport: client)
    }

    private func apply(configuration: YXBConfiguration, transport: any YXBTransport) {
        self.config = configuration
        self.transport = transport
        self.workitemService = YXBWorkitemService(config: configuration, transport: transport)
        self.attachmentService = YXBAttachmentService(config: configuration, transport: transport)
    }

    // MARK: - 提交编排

    /// 提交一次 Bug 上报。
    ///
    /// 编排流程：校验报告 → 获取 Token → 解析工作项类型 → 创建工作项 → 上传附件 → 汇总结果。
    ///
    /// - Parameter report: Bug 报告。
    /// - Returns: 提交结果。工作项创建成功即返回（含 `success` / `partialSuccess`）。
    /// - Throws: 未配置、配置/报告不合法、Token 不可用、工作项类型缺失、创建工作项失败等。
    public func submit(_ report: YXBBugReport) async throws -> YXBSubmitResult {
        guard let config = config,
              let workitemService = workitemService,
              let attachmentService = attachmentService else {
            throw YXBError.notConfigured
        }

        try YXBValidation.validateReport(report)
        let logger: (any YXBLogger)? = config.logger ?? YXBOSLogger.shared

        // 若因 Token 失效/被更换而收到 401，清空 Token 缓存后用新 Token 重试一次。
        do {
            return try await performSubmit(
                report: report,
                config: config,
                workitemService: workitemService,
                attachmentService: attachmentService,
                logger: logger
            )
        } catch let YXBError.httpError(statusCode: 401, _) {
            logger?.log(
                level: .warn,
                message: "[YunxiaoBugReporter] 收到 401，疑似 Token 失效/已更换；清空 Token 缓存后重试一次"
            )
            if let cache = config.cache {
                await cache.remove(forKey: Self.tokenCacheKey)
            }
            return try await performSubmit(
                report: report,
                config: config,
                workitemService: workitemService,
                attachmentService: attachmentService,
                logger: logger
            )
        }
    }

    /// 提交编排主体（不含 401 重试外层）。
    private func performSubmit(
        report: YXBBugReport,
        config: YXBConfiguration,
        workitemService: YXBWorkitemService,
        attachmentService: YXBAttachmentService,
        logger: (any YXBLogger)?
    ) async throws -> YXBSubmitResult {
        let token = try await fetchToken(config: config, logger: logger)
        logger?.log(level: .info, message: "[YunxiaoBugReporter] 开始创建 Bug: \(report.title)")

        let workitemTypeID = try await resolveWorkitemTypeID(
            report: report,
            config: config,
            service: workitemService,
            token: token,
            logger: logger
        )

        let workitemID = try await createWorkitem(
            report: report,
            workitemTypeID: workitemTypeID,
            service: workitemService,
            token: token,
            logger: logger
        )
        logger?.log(level: .info, message: "[YunxiaoBugReporter] 创建 Bug 成功, workitemID=\(workitemID)")

        // 无附件：直接返回成功，避免无谓的网络调用。
        guard !report.attachments.isEmpty else {
            logger?.log(level: .info, message: "[YunxiaoBugReporter] 提交完成（无附件）, status=success")
            return YXBSubmitResult(
                workitemID: workitemID,
                status: .success,
                successfulAttachments: [],
                failedAttachments: []
            )
        }

        logger?.log(level: .info, message: "[YunxiaoBugReporter] 开始上传附件, count=\(report.attachments.count)")
        let attachmentResults = await attachmentService.uploadAll(report.attachments, workitemID: workitemID, token: token)

        let failed = attachmentResults.filter { !$0.success }
        let successful = attachmentResults.filter { $0.success }
        let status: YXBSubmitStatus = failed.isEmpty ? .success : .partialSuccess

        for result in attachmentResults {
            if result.success {
                logger?.log(level: .info, message: "[YunxiaoBugReporter] 附件上传成功: \(result.fileName)")
            } else {
                logger?.log(level: .error, message: "[YunxiaoBugReporter] 附件上传失败: \(result.fileName)")
            }
        }
        logger?.log(level: .info, message: "[YunxiaoBugReporter] 提交完成, status=\(statusDescription(status))")

        return YXBSubmitResult(
            workitemID: workitemID,
            status: status,
            successfulAttachments: successful,
            failedAttachments: failed
        )
    }

    // MARK: - 步骤

    private func fetchToken(config: YXBConfiguration, logger: (any YXBLogger)?) async throws -> String {
        // 命中 Token 缓存：在 TTL 内直接复用，避免重复调用 tokenProvider。
        if config.tokenCacheTTL > 0, let cache = config.cache,
           let cached = await cache.string(forKey: Self.tokenCacheKey) {
            logger?.log(level: .debug, message: "[YunxiaoBugReporter] 命中 Token 缓存")
            return cached
        }
        do {
            let token = try await config.tokenProvider()
            if config.tokenCacheTTL > 0, let cache = config.cache {
                await cache.setString(token, forKey: Self.tokenCacheKey, ttl: config.tokenCacheTTL)
            }
            return token
        } catch {
            logger?.log(level: .error, message: "[YunxiaoBugReporter] 获取 Token 失败")
            throw YXBError.tokenUnavailable(String(describing: error))
        }
    }

    private func resolveWorkitemTypeID(
        report: YXBBugReport,
        config: YXBConfiguration,
        service: YXBWorkitemService,
        token: String,
        logger: (any YXBLogger)?
    ) async throws -> String {
        // 显式指定类型时直接返回，不参与自动解析与缓存。
        if let explicit = config.workitemTypeID, !explicit.isEmpty {
            return explicit
        }

        // 命中工作项类型缓存：按 (edition, organizationID, projectID) 区分项目。
        let key = workitemTypeCacheKey(config: config)
        if let cache = config.cache,
           let cached = await cache.string(forKey: key) {
            logger?.log(level: .debug, message: "[YunxiaoBugReporter] 命中工作项类型缓存: \(cached)")
            return cached
        }

        let types = try await service.fetchBugTypes(token: token)
        guard let selected = YXBWorkitemTypeSelector.select(from: types) else {
            logger?.log(level: .error, message: "[YunxiaoBugReporter] 未找到可用的 Bug 工作项类型")
            throw YXBError.workitemTypeNotFound
        }
        if let cache = config.cache {
            await cache.setString(selected.id, forKey: key, ttl: config.workitemTypeCacheTTL)
        }
        logger?.log(level: .debug, message: "[YunxiaoBugReporter] 自动选择工作项类型: \(selected.id)")
        return selected.id
    }

    // MARK: - 缓存键

    /// Token 缓存键（全局唯一，与项目无关）。
    private static let tokenCacheKey = "token"

    /// 工作项类型缓存键，按版本/组织/项目区分。
    private func workitemTypeCacheKey(config: YXBConfiguration) -> String {
        let org = config.organizationID ?? "none"
        return "workitemType.\(config.edition).\(org).\(config.projectID)"
    }

    private func createWorkitem(
        report: YXBBugReport,
        workitemTypeID: String,
        service: YXBWorkitemService,
        token: String,
        logger: (any YXBLogger)?
    ) async throws -> String {
        do {
            return try await service.createWorkitem(report: report, workitemTypeID: workitemTypeID, token: token)
        } catch {
            let yxb: YXBError = (error as? YXBError) ?? .workitemCreationFailed(String(describing: error))
            logger?.log(level: .error, message: "[YunxiaoBugReporter] 创建 Bug 失败")
            throw yxb
        }
    }

    // MARK: - 列表查询（供宿主构建选择 UI）

    /// 查询当前项目下的 Bug 工作项类型列表，用于构建「工作项类型」选择器。
    /// - Returns: 可用的工作项类型（已按 category=Bug 过滤由服务端控制；调用方可用 `YXBWorkitemTypeSelector` 进一步筛选）。
    /// - Throws: 未配置、Token 不可用、网络/接口错误。
    public func listBugTypes() async throws -> [YXBWorkitemType] {
        guard let config = config, let workitemService = workitemService else {
            throw YXBError.notConfigured
        }
        let logger: (any YXBLogger)? = config.logger ?? YXBOSLogger.shared
        do {
            let token = try await fetchToken(config: config, logger: logger)
            return try await workitemService.fetchBugTypes(token: token)
        } catch let YXBError.httpError(statusCode: 401, _) {
            logger?.log(
                level: .warn,
                message: "[YunxiaoBugReporter] 收到 401，疑似 Token 失效/已更换；清空 Token 缓存后重试一次"
            )
            if let cache = config.cache {
                await cache.remove(forKey: Self.tokenCacheKey)
            }
            let token = try await fetchToken(config: config, logger: logger)
            return try await workitemService.fetchBugTypes(token: token)
        }
    }

    /// 查询当前项目的成员列表，用于构建「负责人」选择器。
    /// - Returns: 项目成员（id 为工作项体系用户标识，可直接作为 `assignedTo`）。
    /// - Throws: 未配置、Token 不可用、网络/接口错误（如 PAT 缺少「项目成员 只读」权限）。
    public func listProjectMembers() async throws -> [YXBMember] {
        guard let config = config, let workitemService = workitemService else {
            throw YXBError.notConfigured
        }
        let logger: (any YXBLogger)? = config.logger ?? YXBOSLogger.shared
        do {
            let token = try await fetchToken(config: config, logger: logger)
            return try await workitemService.fetchProjectMembers(token: token)
        } catch let YXBError.httpError(statusCode: 401, _) {
            logger?.log(
                level: .warn,
                message: "[YunxiaoBugReporter] 收到 401，疑似 Token 失效/已更换；清空 Token 缓存后重试一次"
            )
            if let cache = config.cache {
                await cache.remove(forKey: Self.tokenCacheKey)
            }
            let token = try await fetchToken(config: config, logger: logger)
            return try await workitemService.fetchProjectMembers(token: token)
        }
    }

    private func statusDescription(_ status: YXBSubmitStatus) -> String {
        switch status {
        case .success: return "success"
        case .partialSuccess: return "partialSuccess"
        }
    }
}

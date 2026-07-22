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
        let resolvedTransport = transport ?? YXBHTTPClient(timeout: configuration.timeout)
        apply(configuration: configuration, transport: resolvedTransport)
    }

    /// 配置 SDK。重复调用会覆盖之前的配置。
    public func configure(_ configuration: YXBConfiguration) throws {
        try YXBValidation.validateConfiguration(configuration)
        let client = YXBHTTPClient(timeout: configuration.timeout)
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
        let logger = config.logger

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
        do {
            return try await config.tokenProvider()
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
        if let explicit = config.workitemTypeID, !explicit.isEmpty {
            return explicit
        }
        let types = try await service.fetchBugTypes(token: token)
        guard let selected = YXBWorkitemTypeSelector.select(from: types) else {
            logger?.log(level: .error, message: "[YunxiaoBugReporter] 未找到可用的 Bug 工作项类型")
            throw YXBError.workitemTypeNotFound
        }
        logger?.log(level: .debug, message: "[YunxiaoBugReporter] 自动选择工作项类型: \(selected.id)")
        return selected.id
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

    private func statusDescription(_ status: YXBSubmitStatus) -> String {
        switch status {
        case .success: return "success"
        case .partialSuccess: return "partialSuccess"
        }
    }
}

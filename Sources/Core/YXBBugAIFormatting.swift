import Foundation

/// AI 结构化整理协议（扩展点，暂未接入）。
///
/// 设计目标（见产品方案）：把用户的「一句话现象描述 + 自动采集的上下文」整理为规范的
/// 标题、复现步骤、严重程度建议等结构化字段，减少移动端输入。
///
/// 安全约束（产品方案第十节）：
/// - AI 调用失败时**不得抛出、不得阻塞**提交流程，调用方应回退到用户手动填写的内容；
/// - API Key / 模型地址不应硬编码在 SDK 内，由宿主或服务端代理注入（如实现内部持有
///   `tokenProvider` 式的凭证闭包，或直接走业务服务端统一代理）；
/// - AI 不得修改设备、版本、日志等客观数据，不得凭空编造复现步骤；
/// - 完整截图是否传给 AI 应由配置开关控制。
///
/// TODO: 实现并注入具体的大模型 / 云服务实现；在 `SubmitView` 的提交流程中调用
/// （参考 `SubmitView.submit()` 中标注 `// TODO: AI 结构化整理` 的位置）。
public protocol YXBBugAIFormatting {
    /// 根据用户输入与自动采集上下文，整理为结构化草稿。
    /// - Parameters:
    ///   - userDescription: 用户描述的核心现象（可来自语音转写）。
    ///   - context: 自动采集的设备 / App / 页面 / 网络上下文。
    /// - Returns: 整理后的结构化结果（标题建议、复现步骤、严重程度等）。
    func format(userDescription: String, context: YXBBugContext) async throws -> YXBBugAIResult
}

/// AI 整理后的结构化结果（占位聚合，供接入时使用）。
///
/// 字段对齐产品方案的推荐 JSON：`suggestedTitle` / `reproductionSteps` / `severity` /
/// `missingInformation`。实际接入时可直接映射，无需改动 `YXBBugReport`。
public struct YXBBugAIResult: Sendable {
    /// AI 建议的标题。
    public var suggestedTitle: String?
    /// AI 整理的复现步骤（基于 recentActions，不添加不存在的操作）。
    public var reproductionSteps: [String]
    /// AI 建议的严重程度。
    public var severity: YXBSeverity?
    /// 信息不足、需用户确认或补充的字段。
    public var missingInformation: [String]

    public init(
        suggestedTitle: String? = nil,
        reproductionSteps: [String] = [],
        severity: YXBSeverity? = nil,
        missingInformation: [String] = []
    ) {
        self.suggestedTitle = suggestedTitle
        self.reproductionSteps = reproductionSteps
        self.severity = severity
        self.missingInformation = missingInformation
    }
}

import Foundation

/// 问题类型（与产品方案中的快捷分类一致）。
public enum YXBIssueType: String, CaseIterable, Identifiable {
    case ui        // UI
    case function  // 功能
    case crash     // 崩溃
    case lag       // 卡顿
    case network   // 网络
    case data      // 数据

    public var id: String { rawValue }

    /// UI 展示名。
    public var displayName: String {
        switch self {
        case .ui: return "UI"
        case .function: return "功能"
        case .crash: return "崩溃"
        case .lag: return "卡顿"
        case .network: return "网络"
        case .data: return "数据"
        }
    }

    /// 上报到云效的标签（稳定、可读）。
    public var label: String { "问题类型:\(rawValue)" }
}

/// 严重程度（云效常见取值：blocker / critical / major / minor）。
public enum YXBSeverity: String, CaseIterable, Identifiable {
    case blocker  // 阻塞
    case critical // 严重
    case major    // 一般
    case minor    // 建议

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blocker: return "阻塞"
        case .critical: return "严重"
        case .major: return "一般"
        case .minor: return "建议"
        }
    }

    public var label: String { "严重程度:\(rawValue)" }
}

/// 发生频率。
public enum YXBFrequency: String, CaseIterable, Identifiable {
    case always     // 必现
    case sometimes  // 偶现
    case first      // 首次出现

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .always: return "必现"
        case .sometimes: return "偶现"
        case .first: return "首次出现"
        }
    }

    public var label: String { "发生频率:\(rawValue)" }
}

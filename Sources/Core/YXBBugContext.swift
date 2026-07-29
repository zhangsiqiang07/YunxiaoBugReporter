import Foundation
import UIKit

/// 一次 Bug 上报的上下文（设备 / App / 页面 / 网络 / 操作轨迹 / 最近网络请求等）。
///
/// 设计原则：**宿主采集、Pod 只消费快照**。
/// - 设备型号、系统版本、App 版本、Build 等可在 SDK 内直接获取，由 `YXBBugContextCollector` 自动填充；
/// - 当前页面、路由、网络类型、最近操作轨迹、最近网络请求等**需宿主埋点采集**，
///   由宿主在触发点（如 DoKit 长按）调用 `snapshot()` 冻结为 `YXBHostContext`，
///   再传给 `SubmitView(hostContext:)`；**SDK 不依赖宿主的埋点 / 网络层**；
/// - 网络请求与响应会由宿主在 Debug 环境注入；认证字段必须在采集侧脱敏。
public struct YXBBugContext {
    public var appVersion: String?
    public var build: String?
    /// 机型代号，如 `iPhone17,1`。完整市场名需对照表，首期返回代号已足够定位。
    public var deviceModel: String?
    /// 系统版本号，如 `17.0`。
    public var osVersion: String?
    /// 当前页面类名 / 标识；需宿主接入页面埋点（TODO）。
    public var page: String?
    /// 当前路由；需宿主接入路由埋点（TODO）。
    public var route: String?
    /// 网络类型（Wi-Fi / 蜂窝 / 无）；需宿主接入网络状态（TODO）。
    public var network: String?
    /// 截图数量（截至采集时刻）。
    public var screenshotCount: Int
    /// 采集时间戳。
    public var timestamp: Date
    /// 最近操作轨迹（文本摘要）；由宿主采集后通过 `YXBHostContext` 快照注入。
    public var recentActions: [String]
    /// 最近网络请求面包屑（请求与响应仅脱敏认证信息）；
    /// SDK 自身不采集网络，需宿主在统一网络层记录并通过 `YXBHostContext` 快照注入。
    public var recentRequests: [YXBNetworkBreadcrumb]
    /// 宿主自定义的、已脱敏的补充上下文。SDK 不解释字段含义，仅用于描述和 AI 整理上下文。
    public var supplementaryInfo: [String: String]

    public init(
        appVersion: String? = nil,
        build: String? = nil,
        deviceModel: String? = nil,
        osVersion: String? = nil,
        page: String? = nil,
        route: String? = nil,
        network: String? = nil,
        screenshotCount: Int = 0,
        timestamp: Date = Date(),
        recentActions: [String] = [],
        recentRequests: [YXBNetworkBreadcrumb] = [],
        supplementaryInfo: [String: String] = [:]
    ) {
        self.appVersion = appVersion
        self.build = build
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.page = page
        self.route = route
        self.network = network
        self.screenshotCount = screenshotCount
        self.timestamp = timestamp
        self.recentActions = recentActions
        self.recentRequests = recentRequests
        self.supplementaryInfo = Self.normalizedSupplementaryInfo(supplementaryInfo)
    }

    /// 用于「描述」字段的环境信息行（Markdown 列表）。
    public var descriptionLines: [String] {
        var lines: [String] = []

        if let v = appVersion, let b = build {
            lines.append("- App：\(v)（\(b)）")
        } else if let v = appVersion {
            lines.append("- App：\(v)")
        }

        var sys = "iOS"
        if let os = osVersion { sys += " \(os)" }
        if let dm = deviceModel { sys += "（\(dm)）" }
        lines.append("- 系统：\(sys)")

        lines.append(page.map { "- 页面：\($0)" } ?? "- 页面：待采集")
        if let r = route { lines.append("- 路由：\(r)") }
        lines.append(network.map { "- 网络：\($0)" } ?? "- 网络：待采集")
        lines.append("- 截图：\(screenshotCount) 张")

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        lines.append("- 时间：\(df.string(from: timestamp))")

        if !recentActions.isEmpty {
            lines.append("- 最近操作：\(recentActions.joined(separator: " →\n"))")
        }

        for (key, value) in supplementaryInfo.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            lines.append("- \(key)：\(value)")
        }

        return lines
    }

    /// 自定义信息按纯文本处理：限制条目/长度、压平换行，避免外部值插入 Markdown 标题或代码围栏。
    static func normalizedSupplementaryInfo(_ info: [String: String]) -> [String: String] {
        let maximumEntries = 20
        let maximumKeyLength = 80
        let maximumValueLength = 500
        var result: [String: String] = [:]

        for (rawKey, rawValue) in info.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            guard result.count < maximumEntries else { break }
            let key = compactSupplementaryText(rawKey, maximumLength: maximumKeyLength)
            let value = compactSupplementaryText(rawValue, maximumLength: maximumValueLength)
            guard !key.isEmpty, !value.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    private static func compactSupplementaryText(_ value: String, maximumLength: Int) -> String {
        let compact = value
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > maximumLength else { return compact }
        return String(compact.prefix(maximumLength)) + "…"
    }
}

/// 上下文采集器：收集可在 SDK 内直接获取的设备与 App 信息。
///
/// 页面 / 路由 / 网络 / 最近操作 / 最近网络请求等需宿主埋点，由宿主冻结为
/// `YXBHostContext` 快照后通过 `SubmitView(hostContext:)` 注入；本采集器仅负责设备 / App 维度。
public enum YXBBugContextCollector {
    /// 采集设备与 App 维度信息；其他维度由参数注入（宿主埋点），未提供则为占位。
    /// 注意：`recentRequests` 始终由宿主注入（SDK 不采集网络），此处仅透传、默认空。
    public static func collect(
        screenshotCount: Int,
        page: String? = nil,
        route: String? = nil,
        network: String? = nil,
        recentActions: [String] = [],
        recentRequests: [YXBNetworkBreadcrumb] = []
    ) -> YXBBugContext {
        let bundle = Bundle.main.infoDictionary
        let appVersion = bundle?["CFBundleShortVersionString"] as? String
        let build = bundle?[kCFBundleVersionKey as String] as? String
        let device = UIDevice.current

        return YXBBugContext(
            appVersion: appVersion,
            build: build,
            deviceModel: machineName(),
            osVersion: device.systemVersion,
            page: page,
            route: route,
            network: network,
            screenshotCount: screenshotCount,
            timestamp: Date(),
            recentActions: recentActions,
            recentRequests: recentRequests
        )
    }

    /// 获取设备机型代号（如 `iPhone17,1`）。
    private static func machineName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        var identifier = ""
        for child in mirror.children {
            if let value = child.value as? Int8, value != 0 {
                identifier.append(String(UnicodeScalar(UInt8(value))))
            }
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}

/// 单条网络请求「面包屑」：随 Bug 上报附带的最近网络轨迹。
///
/// **隐私红线（宿主侧必须遵守）**：认证相关信息必须脱敏，至少包括：
/// - `Authorization` / `Cookie` 等鉴权头；
/// - URL query 与 JSON body 中的 token、credential、api key 等认证字段。
/// 完整请求与响应仅用于受控 Debug 上报，宿主需确保云效项目的访问权限与留存合规。
public struct YXBNetworkBreadcrumb: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// HTTP 方法，如 `GET` / `POST`。
    public let method: String
    /// 请求路径。
    public let path: String
    /// 请求 Header（认证字段已脱敏）。
    public let requestHeaders: [String: String]
    /// 请求 Body（认证字段已脱敏）。
    public let requestBody: String?
    /// 响应状态码；请求失败（如超时、无网络）时为 `nil`。
    public let statusCode: Int?
    /// 耗时（毫秒）。
    public let durationMs: Int
    /// 错误摘要（如 `timeout` / `noNetwork` / `decodingFailed`）；无错误为 `nil`。
    public let error: String?
    /// 响应 Header（认证字段已脱敏）。
    public let responseHeaders: [String: String]
    /// 响应 Body（认证字段已脱敏）。
    public let responseBody: String?
    /// 请求发生时间。
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        method: String,
        path: String,
        requestHeaders: [String: String] = [:],
        requestBody: String? = nil,
        statusCode: Int?,
        durationMs: Int,
        error: String?,
        responseHeaders: [String: String] = [:],
        responseBody: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.method = method
        self.path = path
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.error = error
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.timestamp = timestamp
    }
}

/// 宿主在触发点（如 DoKit 长按）一次性冻结的上下文快照；SDK 只消费、不采集。
///
/// 设计原则：**宿主采集、Pod 只消费快照**。
/// - 设备 / App 维度由 SDK 在 `onAppear` 自行采集（`YXBBugContextCollector`）；
/// - 页面 / 路由 / 网络 / 操作轨迹 / 最近网络请求等需宿主埋点，由宿主调用 `snapshot()`
///   冻结为 `YXBHostContext`，再传给 `SubmitView(hostContext:)`。
///   这样可避免进入上报页后 SDK 自身的网络请求污染「最近网络」；
/// - SDK 不依赖宿主的埋点框架或网络层；双方仅通过本结构体契约解耦。
public struct YXBHostContext: Sendable {
    /// 当前页面标识（如 `PetDetailViewController`）。
    public let page: String?
    /// 当前路由（脱敏后的形式，如 `pet/detail`）。
    public let route: String?
    /// 网络类型（`Wi-Fi` / `蜂窝` / `无网络`）。
    public let network: String?
    /// 最近操作轨迹（文本摘要），保留最近若干条。
    public let recentActions: [String]
    /// 最近网络请求面包屑（已脱敏），保留最近若干条。
    public let recentRequests: [YXBNetworkBreadcrumb]
    /// 宿主自定义、已脱敏的补充信息（如登录状态、灰度实验、租户）。
    public let supplementaryInfo: [String: String]

    public init(
        page: String?,
        route: String?,
        network: String?,
        recentActions: [String],
        recentRequests: [YXBNetworkBreadcrumb],
        supplementaryInfo: [String: String] = [:]
    ) {
        self.page = page
        self.route = route
        self.network = network
        self.recentActions = recentActions
        self.recentRequests = recentRequests
        self.supplementaryInfo = YXBBugContext.normalizedSupplementaryInfo(supplementaryInfo)
    }
}

import Foundation
import UIKit

/// 一次 Bug 上报自动采集的上下文（设备 / App / 页面 / 网络 / 操作轨迹等）。
///
/// 设计原则（见产品方案）：
/// - 设备型号、系统版本、App 版本、Build 等可在 SDK 内直接获取，立即填充；
/// - 当前页面、路由、网络类型、最近操作轨迹等**需要宿主接入埋点**，当前为 `nil` / 占位，
///   由宿主通过 `YXBBugContextCollector` 之外的接入点补充（TODO）；
/// - 敏感字段（如用户 ID、Authorization、Cookie、手机号、完整请求体）不应进入上下文，
///   由宿主在埋点侧自行脱敏。
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
    /// 最近操作轨迹（文本摘要）；需宿主接入操作埋点（TODO）。
    public var recentActions: [String]

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
        recentActions: [String] = []
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
            lines.append("- 最近操作：\(recentActions.joined(separator: " → "))")
        }

        return lines
    }
}

/// 上下文采集器：收集可在 SDK 内直接获取的设备和 App 信息。
///
/// 页面 / 路由 / 网络 / 最近操作等需要宿主埋点，调用方应传入已采集的结果，
/// 或通过宿主侧埋点接口补充后再构造 `YXBBugContext`。
public enum YXBBugContextCollector {
    /// 采集设备与 App 维度信息；其他维度由参数注入（宿主埋点），未提供则为占位。
    public static func collect(
        screenshotCount: Int,
        page: String? = nil,
        route: String? = nil,
        network: String? = nil,
        recentActions: [String] = []
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
            recentActions: recentActions
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

import Foundation
import Network

/// 宿主侧证据采集器（示例 / 模板代码，**不属于 SDK**）。
///
/// 职责：在宿主 App 内持续环形缓冲「页面 / 路由 / 操作 / 网络请求 / 网络状态」，
/// 在触发点（如 DoKit 长按）调用 `snapshot()` 一次性冻结为 `YXBHostContext`，
/// 再交给 `SubmitView(hostContext:)`。**SDK 完全不感知本类的存在，仅消费快照**，
/// 因此 SDK 不依赖宿主的埋点框架或网络层。
///
/// 真实接入建议：
/// - 页面 / 路由：在 `viewDidAppear`、路由跳转处调用 `enter(page:route:)`；
/// - 操作：在关键按钮点击、Tab 切换、失败提示处调用 `track(action:)`；
/// - 网络：在统一网络层（Alamofire `EventMonitor` 或现有请求封装）的成功 / 失败回调里
///   调用 `recordRequest(...)`，传入**脱敏后的 path**（不要带 query、不要带鉴权头、
///   不要带请求 / 响应 body，不要带手机号等 PII）；
/// - 网络状态：本类已用 `NWPathMonitor` 自动维护 `network`，无需手动调用。
final class ZJBugEvidenceCollector {

    static let shared = ZJBugEvidenceCollector()

    /// 操作轨迹环形缓冲上限。
    private let maxActions = 50
    /// 网络请求面包屑环形缓冲上限。
    private let maxRequests = 20

    private let queue = DispatchQueue(label: "com.example.ZJBugEvidenceCollector")
    private let monitorQueue = DispatchQueue(label: "com.example.ZJBugEvidenceCollector.monitor")

    private var page: String?
    private var route: String?
    private var network: String = "未知"
    private var recentActions: [String] = []
    private var recentRequests: [YXBNetworkBreadcrumb] = []

    private let monitor = NWPathMonitor()

    private init() {
        startNetworkMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - 采集 API（宿主在埋点 / 网络层调用）

    /// 记录页面曝光 / 路由跳转。
    func enter(page: String, route: String) {
        queue.async { [weak self] in
            self?.page = page
            self?.route = route
        }
    }

    /// 记录一条用户操作（保留最近 `maxActions` 条，新的在前）。
    func track(action: String) {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var next = self.recentActions
            next.insert(trimmed, at: 0)
            if next.count > self.maxActions { next = Array(next.prefix(self.maxActions)) }
            self.recentActions = next
        }
    }

    /// 记录一条网络请求。`path` 必须是**脱敏后**的路径（不含 query / 鉴权头 / 敏感参数）。
    /// - Parameters:
    ///   - method: HTTP 方法。
    ///   - path: 脱敏后的路径（如 `/api/pet/detail`）。
    ///   - statusCode: 响应状态码；请求失败（超时 / 无网络）时为 `nil`。
    ///   - durationMs: 耗时（毫秒）。
    ///   - error: 错误摘要（如 `timeout`）；无错误为 `nil`。
    func recordRequest(
        method: String,
        path: String,
        statusCode: Int?,
        durationMs: Int,
        error: String?
    ) {
        let crumb = YXBNetworkBreadcrumb(
            method: method,
            path: path,
            statusCode: statusCode,
            durationMs: durationMs,
            error: error
        )
        queue.async { [weak self] in
            guard let self else { return }
            var next = self.recentRequests
            next.insert(crumb, at: 0)
            if next.count > self.maxRequests { next = Array(next.prefix(self.maxRequests)) }
            self.recentRequests = next
        }
    }

    // MARK: - 冻结快照

    /// 在触发点（如 DoKit 长按）调用，一次性冻结当前证据为 `YXBHostContext`。
    /// 冻结后其值不再随后续页面 / 网络变化，避免上报页内 SDK 自身请求污染「最近网络」。
    func snapshot() -> YXBHostContext {
        queue.sync {
            YXBHostContext(
                page: page,
                route: route,
                network: network,
                recentActions: recentActions,
                recentRequests: recentRequests
            )
        }
    }

    // MARK: - 网络状态监听

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let value: String
            if path.usesInterfaceType(.wifi) {
                value = "Wi-Fi"
            } else if path.usesInterfaceType(.cellular) {
                value = "蜂窝"
            } else if path.status == .unsatisfied {
                value = "无网络"
            } else {
                value = "未知"
            }
            self?.queue.async { [weak self] in
                self?.network = value
            }
        }
        monitor.start(queue: monitorQueue)
    }
}

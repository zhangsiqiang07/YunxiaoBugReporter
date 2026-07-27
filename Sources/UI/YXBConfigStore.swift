import Foundation
import SwiftUI

/// SDK 内置的配置存储（可观察对象），用于在宿主 App 与 SDK 自带 UI 之间共享可变配置。
///
/// 与早期 Example 中的 `DemoConfigStore` 不同，本类**不硬编码任何凭据**：
/// 域名、组织 ID、默认 Token、默认负责人均由宿主注入
/// （`domain` / `organizationID` / `defaultToken` / `defaultAssignedTo`）。
/// 这些注入参数**全部带默认值（空字符串）**，因此可直接 `YXBConfigStore()` 创建实例，
/// 随后在代码中按需赋值（如 `store.domain = ...`、`store.token = ...`），SDK 不会写入任何真实凭据，
/// 可独立分发。
///
/// 本类负责把存储内容转换为 SDK 的 `YXBConfiguration`：
/// - `isConfigured` / `validationErrors()` 判断是否满足进入主界面的最小配置（项目 ID 必填；负责人于提交时校验）；
/// - `save()` 持久化可变配置（明文写入 UserDefaults）；
/// - `buildConfiguration()` 构造 SDK 配置，域名/组织ID 来自注入值，
///   `tokenProvider` 实时返回（用户填写的）Token，留空时回退 `defaultToken`。
/// - `defaultAssignedTo`（可选）允许宿主注入默认负责人（用户 ID），未显式选择时作为回退，
///   提交时自动选用，行为与 `defaultToken` 一致。
///
/// 域名 / 组织 ID 由宿主注入且通常不变化，故不持久化；其余可变字段（项目、负责人、Token、
/// 缓存设置等）持久化，便于宿主 App 重启后保留用户上次的选择。
public final class YXBConfigStore: ObservableObject {
    /// 宿主注入的云效服务域名（如 `https://openapi-rdc.aliyuncs.com`）。
    /// 可在初始化时传入，也可在初始化后于代码中直接赋值（默认空字符串）。
    public var domain: String = ""
    /// 宿主注入的组织 ID（中心版必填）。
    /// 可在初始化时传入，也可在初始化后于代码中直接赋值（默认空字符串）。
    public var organizationID: String = ""
    /// 注入的默认 Token；当用户未显式修改 Token 时作为回退值。
    /// 可在初始化时传入，也可在初始化后于代码中直接赋值（默认空字符串）。
    public var defaultToken: String = ""
    /// 宿主可注入的默认负责人（用户 ID）。未显式选择负责人时作为回退值，行为类似 `defaultToken`。
    /// 可在初始化时传入，也可在初始化后于代码中直接赋值（默认空字符串）。
    /// 赋值时若当前 `assignedTo` 仍为空，会自动将其种子为默认负责人，使 UI 默认选中该成员；
    /// 一旦用户显式选择过负责人（assignedTo 非空），默认负责人不再覆盖既有选择。
    public var defaultAssignedTo: String = "" {
        didSet {
            let trimmedDefault = defaultAssignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDefault.isEmpty else { return }
            if assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                assignedTo = trimmedDefault
            }
        }
    }

    @Published var editionRaw = "standard"
    @Published var projectID = ""
    /// 负责人（指派给）用户 ID。可在代码中直接赋值，也已由 SDK 内置 UI 绑定。
    @Published public var assignedTo = ""
    @Published var assignedToName = ""
    @Published var workitemTypeID = ""
    @Published var cacheEnabled = true
    @Published var cacheBackendRaw = "userDefaults"
    @Published var workitemTypeCacheTTL = 3600.0
    @Published var tokenCacheTTL = 300.0

    /// 云效访问 Token。初始默认取自注入的 `defaultToken`，可在配置页修改，
    /// 也可在代码中直接赋值（如 `store.token = ...`）。
    @Published public var token: String

    private let defaultsKey: String

    public init(
        domain: String = "",
        organizationID: String = "",
        defaultToken: String = "",
        defaultAssignedTo: String = "",
        edition: YXBConfiguration.Edition = .standard,
        defaultsKey: String = "com.yunxiao.bugreporter.config.v1"
    ) {
        self.domain = domain
        self.organizationID = organizationID
        self.defaultToken = defaultToken
        self.defaultAssignedTo = defaultAssignedTo
        self.defaultsKey = defaultsKey
        self.token = defaultToken
        self.editionRaw = edition == .region ? "region" : "standard"
        load()
        // 与 Token 回退一致：未显式选择负责人时，回退到注入的默认负责人。
        if assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assignedTo = defaultAssignedTo
        }
    }

    public var edition: YXBConfiguration.Edition {
        editionRaw == "region" ? .region : .standard
    }

    /// 是否已具备进入主界面所需的最小配置（仅要求项目 ID；负责人在提交时校验）。
    public var isConfigured: Bool {
        validationErrors().isEmpty
    }

    /// 返回所有不满足的配置问题；为空表示可进入主界面。
    /// 仅校验「项目 ID」必填；「负责人」(assignedTo) 不再作为配置页必填项，
    /// 可在提交页从成员列表选择，留空时于提交时再校验（见 `SubmitView.submit`）。
    /// 域名 / 组织 ID / Token 来自注入值，始终存在，不在此校验。
    public func validationErrors() -> [String] {
        var issues: [String] = []
        if projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("请填写项目 ID")
        }
        return issues
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let persisted = try? JSONDecoder().decode(PersistedConfig.self, from: data) else {
            return
        }
        editionRaw = persisted.editionRaw
        projectID = persisted.projectID
        assignedTo = persisted.assignedTo
        assignedToName = persisted.assignedToName
        workitemTypeID = persisted.workitemTypeID
        cacheEnabled = persisted.cacheEnabled
        cacheBackendRaw = persisted.cacheBackendRaw
        workitemTypeCacheTTL = persisted.workitemTypeCacheTTL
        tokenCacheTTL = persisted.tokenCacheTTL
        // 仅在用户曾显式保存过 Token 时才覆盖默认值；留空则继续回退到注入的默认 Token。
        if !persisted.token.isEmpty {
            token = persisted.token
        }
    }

    public func save() {
        let persisted = PersistedConfig(
            editionRaw: editionRaw,
            projectID: projectID,
            assignedTo: assignedTo,
            assignedToName: assignedToName,
            workitemTypeID: workitemTypeID,
            cacheEnabled: cacheEnabled,
            cacheBackendRaw: cacheBackendRaw,
            workitemTypeCacheTTL: workitemTypeCacheTTL,
            tokenCacheTTL: tokenCacheTTL,
            token: token
        )
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// 解析后的 Token：用户填写值优先，留空回退到注入的默认 Token。
    private var resolvedToken: String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultToken : trimmed
    }

    /// 构造 SDK 配置。域名 / 组织 ID 取自注入值，Token 取自用户可编辑的值
    /// （`resolvedToken`，留空回退默认 Token）。
    func buildConfiguration() throws -> YXBConfiguration {
        let trimmedProject = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssignee = assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = workitemTypeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedToken = self.resolvedToken

        let cache: (any YXBCache)? = cacheEnabled
            ? (cacheBackendRaw == "userDefaults" ? YXBUserDefaultsCache() : YXBInMemoryCache()) as any YXBCache
            : nil

        return YXBConfiguration(
            domain: domain,
            edition: edition,
            organizationID: organizationID,
            projectID: trimmedProject,
            workitemTypeID: trimmedType.isEmpty ? nil : trimmedType,
            assignedTo: trimmedAssignee,
            tokenProvider: { resolvedToken },
            cache: cache,
            workitemTypeCacheTTL: workitemTypeCacheTTL,
            tokenCacheTTL: tokenCacheTTL
        )
    }

    /// 构造仅用于「拉取组织项目列表」的 SDK 配置。
    ///
    /// `configure()` 要求 `projectID` / `assignedTo` 非空，但项目列表接口（SearchProjects）
    /// 仅依赖 `organizationID`，与这两个字段无关。因此当它们尚未填写时，填入占位值以通过
    /// `configure()` 校验；占位值不会被项目列表请求使用（请求路径不含 projectID）。
    func buildConfigurationForProjectListing() throws -> YXBConfiguration {
        let base = try buildConfiguration()
        let safeProject = base.projectID.isEmpty ? "PLACEHOLDER_NOT_USED" : base.projectID
        let safeAssignee = base.assignedTo.isEmpty ? "PLACEHOLDER_NOT_USED" : base.assignedTo
        // 与 buildConfiguration 一致：先把已解析 Token 取到本地值（String 可 Sendable），
        // 避免了直接捕获 self 或调用 `async throws` 的 base.tokenProvider 闭包。
        let resolvedToken = self.resolvedToken
        return YXBConfiguration(
            domain: domain,
            edition: edition,
            organizationID: organizationID,
            projectID: safeProject,
            workitemTypeID: base.workitemTypeID,
            assignedTo: safeAssignee,
            tokenProvider: { resolvedToken },
            cache: base.cache,
            workitemTypeCacheTTL: base.workitemTypeCacheTTL,
            tokenCacheTTL: base.tokenCacheTTL
        )
    }

    /// 构造仅用于「拉取项目成员列表」的 SDK 配置。
    ///
    /// 成员接口为项目级，依赖 `projectID`；但查询成员本身并不需要 `assignedTo`。
    /// 因此当 `assignedTo` 尚未填写时填入占位值以通过 `configure()` 校验，
    /// 该占位值不会被成员请求使用（请求路径不含 assignedTo）。
    func buildConfigurationForMemberListing() throws -> YXBConfiguration {
        let base = try buildConfiguration()
        let safeAssignee = base.assignedTo.isEmpty ? "PLACEHOLDER_NOT_USED" : base.assignedTo
        let resolvedToken = self.resolvedToken
        return YXBConfiguration(
            domain: domain,
            edition: edition,
            organizationID: organizationID,
            projectID: base.projectID,
            workitemTypeID: base.workitemTypeID,
            assignedTo: safeAssignee,
            tokenProvider: { resolvedToken },
            cache: base.cache,
            workitemTypeCacheTTL: base.workitemTypeCacheTTL,
            tokenCacheTTL: base.tokenCacheTTL
        )
    }

    private struct PersistedConfig: Codable {
        var editionRaw: String
        var projectID: String
        var assignedTo: String
        var assignedToName: String
        var workitemTypeID: String
        var cacheEnabled: Bool
        var cacheBackendRaw: String
        var workitemTypeCacheTTL: Double
        var tokenCacheTTL: Double
        var token: String
    }
}

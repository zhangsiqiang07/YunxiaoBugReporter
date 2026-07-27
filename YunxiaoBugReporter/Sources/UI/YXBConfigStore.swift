import Foundation
import SwiftUI

/// SDK 内置的配置存储（可观察对象），用于在宿主 App 与 SDK 自带 UI 之间共享可变配置。
///
/// 与早期 Example 中的 `DemoConfigStore` 不同，本类**不硬编码任何凭据**：
/// 域名、组织 ID、默认 Token 均由宿主在初始化时注入（`domain` / `organizationID` / `defaultToken`），
/// 因此 SDK 可独立分发、不包含演示用的真实 Token。
///
/// 本类负责把存储内容转换为 SDK 的 `YXBConfiguration`：
/// - `isConfigured` / `validationErrors()` 判断是否满足提交所需的最小信息；
/// - `save()` 持久化可变配置（明文写入 UserDefaults）；
/// - `buildConfiguration()` 构造 SDK 配置，域名/组织ID 来自注入值，
///   `tokenProvider` 实时返回（用户填写的）Token，留空时回退 `defaultToken`。
///
/// 域名 / 组织 ID 由宿主注入且通常不变化，故不持久化；其余可变字段（项目、负责人、Token、
/// 缓存设置等）持久化，便于宿主 App 重启后保留用户上次的选择。
public final class YXBConfigStore: ObservableObject {
    /// 宿主注入的云效服务域名（如 `https://openapi-rdc.aliyuncs.com`）。
    public let domain: String
    /// 宿主注入的组织 ID（中心版必填）。
    public let organizationID: String
    /// 注入的默认 Token；当用户未显式修改 Token 时作为回退值。
    private let defaultToken: String

    @Published var editionRaw = "standard"
    @Published var projectID = ""
    @Published var assignedTo = ""
    @Published var assignedToName = ""
    @Published var workitemTypeID = ""
    @Published var cacheEnabled = true
    @Published var cacheBackendRaw = "userDefaults"
    @Published var workitemTypeCacheTTL = 3600.0
    @Published var tokenCacheTTL = 300.0

    /// 云效访问 Token。初始默认取自注入的 `defaultToken`，可在配置页修改。
    @Published var token: String

    private let defaultsKey: String

    public init(
        domain: String,
        organizationID: String,
        defaultToken: String = "",
        edition: YXBConfiguration.Edition = .standard,
        defaultsKey: String = "com.yunxiao.bugreporter.config.v1"
    ) {
        self.domain = domain
        self.organizationID = organizationID
        self.defaultToken = defaultToken
        self.defaultsKey = defaultsKey
        self.token = defaultToken
        self.editionRaw = edition == .region ? "region" : "standard"
        load()
    }

    public var edition: YXBConfiguration.Edition {
        editionRaw == "region" ? .region : .standard
    }

    /// 是否已具备提交所需的最小配置。
    public var isConfigured: Bool {
        validationErrors().isEmpty
    }

    /// 返回所有不满足的配置问题；为空表示配置完整。
    /// 域名 / 组织 ID / Token 来自注入值，始终存在，不在此校验。
    public func validationErrors() -> [String] {
        var issues: [String] = []
        if projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("请填写项目 ID")
        }
        if assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("请填写负责人用户 ID")
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

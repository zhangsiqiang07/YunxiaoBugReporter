import SwiftUI
import YunxiaoBugReporter

/// 演示用配置存储：可变配置（项目 ID、负责人、访问 Token 等）以明文保存在 `UserDefaults`。
///
/// 域名、组织 ID 极少变更，写死在 `DemoConstants` 并在配置页只读展示；
/// **访问 Token 默认可编辑**，初始值取自 `DemoConstants.token`，用户可在配置页修改并保存，
/// 保存后优先使用用户填写值（留空则回退到代码中的默认值）。
///
/// 本类负责把存储内容转换为 SDK 的 `YXBConfiguration`：
/// - `isConfigured` / `validationErrors()` 判断是否满足提交所需的最小信息；
/// - `save()` 持久化可变配置（明文写入 UserDefaults）；
/// - `buildConfiguration()` 构造 SDK 配置，域名/组织ID 取自 `DemoConstants`，
///   `tokenProvider` 实时返回（用户填写的）Token，留空时回退 `DemoConstants.token`。
final class DemoConfigStore: ObservableObject {
    static let shared = DemoConfigStore()

    @Published var editionRaw = "standard"
    @Published var projectID = ""
    @Published var assignedTo = ""
    @Published var assignedToName = ""
    @Published var workitemTypeID = ""
    @Published var cacheEnabled = true
    @Published var cacheBackendRaw = "userDefaults"
    @Published var workitemTypeCacheTTL = 3600.0
    @Published var tokenCacheTTL = 300.0

    /// 云效访问 Token。初始默认取自 `DemoConstants.token`（代码中的值），可在配置页修改。
    @Published var token = DemoConstants.token

    private let defaultsKey = "com.yunxiao.demo.config.v1"

    private init() { load() }

    var edition: YXBConfiguration.Edition {
        editionRaw == "region" ? .region : .standard
    }

    /// 是否已具备提交所需的最小配置。
    var isConfigured: Bool {
        validationErrors().isEmpty
    }

    /// 返回所有不满足的配置问题；为空表示配置完整。
    /// 域名 / 组织 ID / Token 来自 `DemoConstants`，始终存在，不在此校验。
    func validationErrors() -> [String] {
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
        // 仅在用户曾显式保存过 Token 时才覆盖默认值；留空则继续回退到代码中的默认值。
        if !persisted.token.isEmpty {
            token = persisted.token
        }
    }

    func save() {
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

    /// 解析后的 Token：用户填写值优先，留空回退到代码中的默认 Token。
    private var resolvedToken: String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? DemoConstants.token : trimmed
    }

    /// 构造 SDK 配置。域名 / 组织 ID 取自 `DemoConstants`，Token 取自用户可编辑的值
    /// （`resolvedToken`，留空回退代码默认值）。
    func buildConfiguration() throws -> YXBConfiguration {
        let trimmedProject = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssignee = assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = workitemTypeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedToken = self.resolvedToken

        let cache: (any YXBCache)? = cacheEnabled
            ? (cacheBackendRaw == "userDefaults" ? YXBUserDefaultsCache() : YXBInMemoryCache()) as any YXBCache
            : nil

        return YXBConfiguration(
            domain: DemoConstants.domain,
            edition: edition,
            organizationID: DemoConstants.organizationID,
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
            domain: DemoConstants.domain,
            edition: edition,
            organizationID: DemoConstants.organizationID,
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
            domain: DemoConstants.domain,
            edition: edition,
            organizationID: DemoConstants.organizationID,
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

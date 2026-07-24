import SwiftUI
import YunxiaoBugReporter

/// 演示用配置存储：可变配置（项目 ID、负责人等）以明文保存在 `UserDefaults`。
///
/// 域名、组织 ID、Token 极少变更，已写死在 `DemoConstants` 中并在配置页只读展示，
/// 不在此处持久化、也不参与校验。
///
/// 本类负责把存储内容转换为 SDK 的 `YXBConfiguration`：
/// - `isConfigured` / `validationErrors()` 判断是否满足提交所需的最小信息；
/// - `save()` 持久化可变配置（明文写入 UserDefaults）；
/// - `buildConfiguration()` 构造 SDK 配置，域名/组织ID/Token 取自 `DemoConstants`，
///   `tokenProvider` 实时返回该写死的 Token。
final class DemoConfigStore: ObservableObject {
    static let shared = DemoConfigStore()

    @Published var editionRaw = "standard"
    @Published var projectID = ""
    @Published var assignedTo = ""
    @Published var assignedToName = ""
    @Published var workitemTypeID = ""
    @Published var cacheEnabled = false
    @Published var cacheBackendRaw = "memory"
    @Published var workitemTypeCacheTTL = 3600.0
    @Published var tokenCacheTTL = 300.0

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
            tokenCacheTTL: tokenCacheTTL
        )
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// 构造 SDK 配置。域名 / 组织 ID / Token 取自 `DemoConstants`（写死，无需用户填写），
    /// `tokenProvider` 返回该写死的 Token（明文，仅演示用）。
    func buildConfiguration() throws -> YXBConfiguration {
        let trimmedProject = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssignee = assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = workitemTypeID.trimmingCharacters(in: .whitespacesAndNewlines)

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
            tokenProvider: { DemoConstants.token },
            cache: cache,
            workitemTypeCacheTTL: workitemTypeCacheTTL,
            tokenCacheTTL: tokenCacheTTL
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
    }
}

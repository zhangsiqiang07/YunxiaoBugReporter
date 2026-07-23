import SwiftUI
import YunxiaoBugReporter

/// 演示用配置存储：云效连接信息存于 `UserDefaults`，Token 存于钥匙串（Keychain）。
///
/// 同时负责把存储内容转换为 SDK 的 `YXBConfiguration`：
/// - `isConfigured` / `validationErrors()` 判断是否满足提交所需的最小信息；
/// - `save()` 持久化；
/// - `buildConfiguration()` 构造 SDK 配置（Token 通过 Keychain 实时读取）。
final class DemoConfigStore: ObservableObject {
    static let shared = DemoConfigStore()

    @Published var domain = ""
    @Published var editionRaw = "standard"
    @Published var organizationID = ""
    @Published var projectID = ""
    @Published var assignedTo = ""
    @Published var workitemTypeID = ""
    @Published var token = ""
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
    func validationErrors() -> [String] {
        var issues: [String] = []
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDomain.isEmpty {
            issues.append("请填写服务域名")
        } else if let url = URL(string: trimmedDomain),
                  let scheme = url.scheme,
                  ["http", "https"].contains(scheme) == false {
            issues.append("域名需以 http:// 或 https:// 开头")
        } else if URL(string: trimmedDomain) == nil {
            issues.append("域名格式不正确")
        }

        if projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("请填写项目 ID")
        }
        if assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("请填写负责人用户 ID")
        }
        if edition == .standard,
           organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("中心版请填写组织 ID")
        }
        if KeychainStore.hasToken == false {
            issues.append("请填写云效访问 Token")
        }
        return issues
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let persisted = try? JSONDecoder().decode(PersistedConfig.self, from: data) else {
            return
        }
        domain = persisted.domain
        editionRaw = persisted.editionRaw
        organizationID = persisted.organizationID
        projectID = persisted.projectID
        assignedTo = persisted.assignedTo
        workitemTypeID = persisted.workitemTypeID
        cacheEnabled = persisted.cacheEnabled
        cacheBackendRaw = persisted.cacheBackendRaw
        workitemTypeCacheTTL = persisted.workitemTypeCacheTTL
        tokenCacheTTL = persisted.tokenCacheTTL
        token = (try? KeychainStore.readToken()) ?? ""
    }

    func save() {
        let persisted = PersistedConfig(
            domain: domain,
            editionRaw: editionRaw,
            organizationID: organizationID,
            projectID: projectID,
            assignedTo: assignedTo,
            workitemTypeID: workitemTypeID,
            cacheEnabled: cacheEnabled,
            cacheBackendRaw: cacheBackendRaw,
            workitemTypeCacheTTL: workitemTypeCacheTTL,
            tokenCacheTTL: tokenCacheTTL
        )
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.isEmpty {
            KeychainStore.deleteToken()
        } else {
            KeychainStore.saveToken(trimmedToken)
        }
    }

    /// 构造 SDK 配置。`tokenProvider` 在需要 Token 时从 Keychain 读取（不在内存长期持有）。
    func buildConfiguration() throws -> YXBConfiguration {
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrg = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProject = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssignee = assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = workitemTypeID.trimmingCharacters(in: .whitespacesAndNewlines)

        let cache: (any YXBCache)? = cacheEnabled
            ? (cacheBackendRaw == "userDefaults" ? YXBUserDefaultsCache() : YXBInMemoryCache()) as any YXBCache
            : nil

        return YXBConfiguration(
            domain: trimmedDomain,
            edition: edition,
            organizationID: trimmedOrg.isEmpty ? nil : trimmedOrg,
            projectID: trimmedProject,
            workitemTypeID: trimmedType.isEmpty ? nil : trimmedType,
            assignedTo: trimmedAssignee,
            tokenProvider: { try KeychainStore.readToken() },
            cache: cache,
            workitemTypeCacheTTL: workitemTypeCacheTTL,
            tokenCacheTTL: tokenCacheTTL
        )
    }

    private struct PersistedConfig: Codable {
        var domain: String
        var editionRaw: String
        var organizationID: String
        var projectID: String
        var assignedTo: String
        var workitemTypeID: String
        var cacheEnabled: Bool
        var cacheBackendRaw: String
        var workitemTypeCacheTTL: Double
        var tokenCacheTTL: Double
    }
}

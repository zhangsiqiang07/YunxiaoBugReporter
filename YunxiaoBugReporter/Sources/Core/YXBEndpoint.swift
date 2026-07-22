import Foundation

/// API 端点。根据版本（中心版 / Region 版）生成路径。
///
/// 说明：查询 Bug 类型的 `category=Bug` 作为 query 参数，由 `YXBRequestBuilder` 拼接到 URL，
/// 这里只负责路径部分，避免把 `?` 写死在 path 中导致 `URLComponents` 解析丢失 query。
enum YXBEndpoint {
    case workitemTypes
    case workitemTypeFields(workitemTypeId: String)
    case createWorkitem
    case attachments(workitemId: String)

    /// 生成路径（不含域名、不含 query）。
    func path(config: YXBConfiguration) -> String {
        switch self {
        case .workitemTypes:
            return base(config) + "/projects/\(config.projectID)/workitemTypes"
        case .workitemTypeFields(let workitemTypeId):
            return base(config) + "/projects/\(config.projectID)/workitemTypes/\(workitemTypeId)/fields"
        case .createWorkitem:
            return base(config) + "/workitems"
        case .attachments(let workitemId):
            return base(config) + "/workitems/\(workitemId)/attachments"
        }
    }

    /// 版本前缀。
    private func base(_ config: YXBConfiguration) -> String {
        switch config.edition {
        case .standard:
            // organizationID 在配置校验阶段已确保非空（中心版）。
            return "/oapi/v1/projex/organizations/\(config.organizationID ?? "")"
        case .region:
            return "/oapi/v1/projex"
        }
    }
}

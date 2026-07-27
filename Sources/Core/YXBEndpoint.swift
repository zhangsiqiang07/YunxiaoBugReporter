import Foundation

/// API 端点。根据版本（中心版 / Region 版）生成路径。
///
/// 说明：查询 Bug 类型的 `category=Bug` 作为 query 参数，由 `YXBRequestBuilder` 拼接到 URL，
/// 这里只负责路径部分，避免把 `?` 写死在 path 中导致 `URLComponents` 解析丢失 query。
enum YXBEndpoint {
    case workitemTypes
    case workitemTypeFields(workitemTypeId: String)
    case createWorkitem
    case projectMembers
    case projects
    case workitemsSearch
    case attachments(workitemId: String)
    case updateWorkitem(workitemId: String)
    case getWorkitem(workitemId: String)
    case getWorkitemFile(workitemId: String, fileId: String)

    /// 生成路径（不含域名、不含 query）。
    func path(config: YXBConfiguration) -> String {
        switch self {
        case .workitemTypes:
            return base(config) + "/projects/\(config.projectID)/workitemTypes"
        case .workitemTypeFields(let workitemTypeId):
            return base(config) + "/projects/\(config.projectID)/workitemTypes/\(workitemTypeId)/fields"
        case .createWorkitem:
            return base(config) + "/workitems"
        case .projectMembers:
            return base(config) + "/projects/\(config.projectID)/members"
        case .projects:
            // 中心版：/oapi/v1/projex/organizations/{orgId}/projects:search
            // Region 版：/oapi/v1/projex/projects:search
            // 该接口按组织返回项目列表，仅依赖 organizationID，与 projectID 无关。
            return base(config) + "/projects:search"
        case .workitemsSearch:
            // 中心版：/oapi/v1/projex/organizations/{orgId}/workitems:search
            // Region 版：/oapi/v1/projex/workitems:search
            // 该接口按 spaceId（即 projectID）分页搜索工作项，需要 projectID。
            return base(config) + "/workitems:search"
        case .attachments(let workitemId):
            return base(config) + "/workitems/\(workitemId)/attachments"
        case .updateWorkitem(let workitemId):
            return base(config) + "/workitems/\(workitemId)"
        case .getWorkitem(let workitemId):
            return base(config) + "/workitems/\(workitemId)"
        case .getWorkitemFile(let workitemId, let fileId):
            return base(config) + "/workitems/\(workitemId)/files/\(fileId)"
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

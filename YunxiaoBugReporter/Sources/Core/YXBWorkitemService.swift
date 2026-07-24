import Foundation

/// 工作项服务：查询类型、读取字段、创建工作项。
struct YXBWorkitemService {
    let config: YXBConfiguration
    let transport: any YXBTransport
    private let builder: YXBRequestBuilder

    init(config: YXBConfiguration, transport: any YXBTransport) {
        self.config = config
        self.transport = transport
        self.builder = YXBRequestBuilder()
    }

    /// 查询项目下的 Bug 工作项类型列表。
    func fetchBugTypes(token: String) async throws -> [YXBWorkitemType] {
        let request = try builder.build(
            endpoint: .workitemTypes,
            config: config,
            method: "GET",
            token: token,
            query: [URLQueryItem(name: "category", value: "Bug")]
        )
        let response: YXBWorkitemTypesResponse = try await transport.send(request, responseType: YXBWorkitemTypesResponse.self)
        return response.items
    }

    /// 读取指定工作项类型的字段定义（用于构建自定义字段 / 必填字段选择 UI）。
    func fetchTypeFields(workitemTypeId: String, token: String) async throws -> [YXBFieldDefinition] {
        let request = try builder.build(
            endpoint: .workitemTypeFields(workitemTypeId: workitemTypeId),
            config: config,
            method: "GET",
            token: token
        )
        let response: YXBFieldDefinitionsResponse = try await transport.send(request, responseType: YXBFieldDefinitionsResponse.self)
        return response.items
    }

    /// 查询项目成员列表（用于负责人选择 UI）。
    func fetchProjectMembers(token: String) async throws -> [YXBMember] {
        let request = try builder.build(
            endpoint: .projectMembers,
            config: config,
            method: "GET",
            token: token
        )
        let response: YXBMembersResponse = try await transport.send(request, responseType: YXBMembersResponse.self)
        return response.items
    }

    /// 查询组织下的项目列表（用于「项目」选择 UI）。
    ///
    /// 调用云效 `SearchProjects` 接口（`POST .../projects:search`），请求体指定
    /// `orderBy: gmtCreate, sort: desc`，服务端即按创建时间倒序返回；
    /// 这里再兜底按 `createdAt` 降序排序一次，保证「最新建立的项目」排在最前。
    /// - Parameter token: 云效访问令牌。
    /// - Returns: 项目列表（已按创建时间倒序）。
    func fetchOrganizationProjects(token: String) async throws -> [YXBProject] {
        let body: [String: Any] = [
            "orderBy": "gmtCreate",
            "page": 1,
            "perPage": 50,
            "sort": "desc"
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let request = try builder.buildJSON(
            endpoint: .projects,
            config: config,
            token: token,
            method: "POST",
            body: payload
        )
        let response: YXBProjectsResponse = try await transport.send(request, responseType: YXBProjectsResponse.self)
        // 兜底按创建时间降序；缺失创建时间的项排在末尾（保持服务端相对顺序）。
        return response.items.sorted {
            ($0.createdAt ?? 0) > ($1.createdAt ?? 0)
        }
    }

    /// 创建 Bug 工作项，返回工作项 ID。
    func createWorkitem(report: YXBBugReport, workitemTypeID: String, token: String) async throws -> String {
        let body = YXBCreateWorkitemBody(
            spaceId: config.projectID,
            workitemTypeId: workitemTypeID,
            subject: report.title,
            assignedTo: report.assignedTo ?? config.assignedTo,
            description: report.description,
            descriptionFormat: report.format.apiValue,
            customFieldValues: report.customFields,
            labels: report.labels
        )
        let payload = try YXBJSONCoder.encoder.encode(body)
        let request = try builder.buildJSON(
            endpoint: .createWorkitem,
            config: config,
            token: token,
            method: "POST",
            body: payload
        )
        let response: YXBWorkitemCreateResponse = try await transport.send(request, responseType: YXBWorkitemCreateResponse.self)
        return response.id
    }
}

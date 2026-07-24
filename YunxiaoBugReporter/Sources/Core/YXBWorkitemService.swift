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

    /// 查询指定项目下的工作项列表（分页），用于「Bug 列表」展示。
    ///
    /// 调用云效 `SearchWorkitems` 接口（`POST .../workitems:search`），请求体指定
    /// `category: Bug`、`spaceId: projectID`、`spaceType: Project`、`page/perPage` 分页、
    /// 并按 `gmtCreate` 倒序返回。
    /// - Parameters:
    ///   - page: 页码，从 1 开始。
    ///   - perPage: 每页条数（0-200）。
    ///   - category: 工作项类型，默认 `Bug`。
    ///   - token: 云效访问令牌。
    /// - Returns: 本页工作项列表（已按创建时间倒序）。
    func fetchWorkitems(page: Int, perPage: Int, category: String, token: String) async throws -> [YXBWorkitem] {
        let body: [String: Any] = [
            "category": category,
            "spaceId": config.projectID,
            "spaceType": "Project",
            "orderBy": "gmtCreate",
            "page": page,
            "perPage": perPage,
            "sort": "desc"
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let request = try builder.buildJSON(
            endpoint: .workitemsSearch,
            config: config,
            token: token,
            method: "POST",
            body: payload
        )
        let response: YXBWorkitemsResponse = try await transport.send(request, responseType: YXBWorkitemsResponse.self)
        return response.items
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

    /// 更新工作项描述（用于把上传成功的图片片段嵌入描述）。
    ///
    /// 调用云效 `UpdateWorkitem` 接口（`PUT .../workitems/{id}`），请求体为
    /// `{ "description": ..., "formatType": "RICHTEXT" | "MARKDOWN" }`。该接口无响应体。
    /// - Parameters:
    ///   - workitemID: 工作项 ID。
    ///   - description: 新的描述内容（已包含嵌入的图片片段）。
    ///   - format: 描述格式，决定 `formatType` 取值，须与创建时一致。
    ///   - token: 云效访问令牌。
    func updateWorkitemDescription(
        workitemID: String,
        description: String,
        format: YXBDescriptionFormat,
        token: String
    ) async throws {
        let body: [String: Any] = [
            "description": description,
            "formatType": format.apiValue
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let request = try builder.buildJSON(
            endpoint: .updateWorkitem(workitemId: workitemID),
            config: config,
            token: token,
            method: "PUT",
            body: payload
        )
        try await transport.sendWithoutResponse(request)
    }
}

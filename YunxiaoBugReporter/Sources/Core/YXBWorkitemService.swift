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

    /// 读取指定工作项类型的字段定义（可用于后续扩展自定义字段 UI）。
    func fetchTypeFields(workitemTypeId: String, token: String) async throws {
        let request = try builder.build(
            endpoint: .workitemTypeFields(workitemTypeId: workitemTypeId),
            config: config,
            method: "GET",
            token: token
        )
        try await transport.sendWithoutResponse(request)
    }

    /// 创建 Bug 工作项，返回工作项 ID。
    func createWorkitem(report: YXBBugReport, workitemTypeID: String, token: String) async throws -> String {
        let body = YXBCreateWorkitemBody(
            projectId: config.projectID,
            organizationId: config.edition == .standard ? config.organizationID : nil,
            workitemType: workitemTypeID,
            title: report.title,
            description: report.description,
            descriptionFormat: report.format.rawValue,
            assignedTo: report.assignedTo ?? config.assignedTo,
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

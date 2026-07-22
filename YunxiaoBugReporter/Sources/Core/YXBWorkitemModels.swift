import Foundation

/// 工作项类型模型（云效返回）。
struct YXBWorkitemType: Sendable, Decodable {
    let id: String
    let name: String?
    let category: String?
    let enabled: Bool
    let isDefault: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case enabled
        case isDefault = "default"
        case defaultType = "defaultType"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let d1 = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        let d2 = try container.decodeIfPresent(Bool.self, forKey: .defaultType) ?? false
        isDefault = d1 || d2
    }
}

/// 查询工作项类型列表的响应。兼容 `{ "data": [...] }`、直接数组或 `{ "items": [...] }`。
struct YXBWorkitemTypesResponse: Decodable {
    let items: [YXBWorkitemType]

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([YXBWorkitemType].self) {
            items = array
            return
        }
        let container = try decoder.container(keyedBy: YXBAnyCodingKey.self)
        if let array = try? container.decode([YXBWorkitemType].self, forKey: YXBAnyCodingKey(stringValue: "data")) {
            items = array
        } else if let array = try? container.decode([YXBWorkitemType].self, forKey: YXBAnyCodingKey(stringValue: "items")) {
            items = array
        } else {
            items = []
        }
    }
}

/// 创建工作项接口的响应。兼容 `id` / `workitemId` / `workItemId`。
struct YXBWorkitemCreateResponse: Decodable {
    let id: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: YXBAnyCodingKey.self)
        if let value = try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: "id")) {
            id = value
        } else if let value = try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: "workitemId")) {
            id = value
        } else if let value = try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: "workItemId")) {
            id = value
        } else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(codingPath: [], debugDescription: "云效创建工作项响应缺少 ID 字段")
            )
        }
    }
}

/// 上传附件接口的响应。兼容 `id` / `attachmentId` / `fileId`。
struct YXBAttachmentCreateResponse: Decodable {
    let id: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: YXBAnyCodingKey.self)
        if let value = try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: "id")) {
            id = value
        } else if let value = try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: "attachmentId")) {
            id = value
        } else if let value = try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: "fileId")) {
            id = value
        } else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(codingPath: [], debugDescription: "云效上传附件响应缺少 ID 字段")
            )
        }
    }
}

/// 创建工作项请求体。使用默认编码（camelCase），字段名与云效接口对齐。
struct YXBCreateWorkitemBody: Encodable {
    let projectId: String
    let organizationId: String?
    let workitemType: String
    let title: String
    let description: String
    let descriptionFormat: String
    let assignedTo: String
    let customFieldValues: [String: String]
    let labels: [String]
}

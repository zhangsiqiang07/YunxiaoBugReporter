import Foundation

/// 工作项类型模型（云效返回）。公开以便宿主构建类型选择 UI。
public struct YXBWorkitemType: Identifiable, Sendable, Decodable {
    public let id: String
    public let name: String?
    public let category: String?
    public let enabled: Bool
    public let isDefault: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case enabled
        case isDefault = "default"
        case defaultType = "defaultType"
    }

    public init(from decoder: Decoder) throws {
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

/// 创建工作项请求体。字段名严格对齐云效 CreateWorkitem 官方文档（中心版 / Region 版通用）。
///
/// 必填：`spaceId`（项目即空间，等于配置中的 `projectID`）、`subject`、`workitemTypeId`、`assignedTo`。
/// 可选：`description`、`descriptionFormat`、`customFieldValues`、`labels` 等。
struct YXBCreateWorkitemBody: Encodable {
    let spaceId: String
    let workitemTypeId: String
    let subject: String
    let assignedTo: String
    let description: String
    let descriptionFormat: String
    let customFieldValues: [String: String]
    let labels: [String]
}

/// 项目成员模型（云效返回）。公开以便宿主构建负责人选择 UI。
///
/// 云效不同版本/接口的字段命名不一致，这里对 `id` 与 `name` 做多键容错解析，
/// 依次尝试常见字段名，保证在 `projex` 成员接口下都能取到可用标识。
public struct YXBMember: Identifiable, Sendable, Decodable {
    public let id: String
    public let name: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: YXBAnyCodingKey.self)
        let idCandidates = ["id", "identifier", "userId", "accountId", "userIdentifier"]
        id = idCandidates.compactMap { key in
            try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: key))
        }.first ?? ""
        let nameCandidates = ["name", "displayName", "nickName", "realName", "displayNickName"]
        name = nameCandidates.compactMap { key in
            try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: key))
        }.first ?? id
    }
}

/// 项目成员列表响应。兼容 直接数组 / `data` / `members` / `items` / `list` / `projectMembers` 等多种包络。
struct YXBMembersResponse: Decodable {
    let items: [YXBMember]

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([YXBMember].self) {
            items = array
            return
        }
        let container = try decoder.container(keyedBy: YXBAnyCodingKey.self)
        let candidates = ["data", "members", "items", "list", "projectMembers"]
        for key in candidates {
            if let array = try? container.decode([YXBMember].self, forKey: YXBAnyCodingKey(stringValue: key)) {
                items = array
                return
            }
        }
        items = []
    }
}

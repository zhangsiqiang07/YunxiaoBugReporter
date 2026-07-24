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
        let idCandidates = ["id", "identifier", "userId", "userIdentifier", "accountId", "account"]
        id = idCandidates.compactMap { key in
            try? container.decode(String.self, forKey: YXBAnyCodingKey(stringValue: key))
        }.first ?? ""
        // 云效 projex 成员接口实际返回字段为 `userId` / `userName`（直接数组包络）。
        // 这里按展示名优先级容错解析：展示名、用户名、真名、昵称、账号。
        let nameCandidates = ["displayName", "userName", "displayRealName", "displayNickName",
                              "name", "realName", "nickName", "nickname", "account", "loginName"]
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

/// 工作项类型字段定义中的单个选项（单选/多选/层级等）。
public struct YXBFieldOption: Identifiable, Sendable, Decodable {
    public let id: String
    public let value: String
    public let displayValue: String
    public let valueEn: String?

    private enum CodingKeys: String, CodingKey {
        case id, value, displayValue, valueEn
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        displayValue = try container.decodeIfPresent(String.self, forKey: .displayValue) ?? value
        valueEn = try container.decodeIfPresent(String.self, forKey: .valueEn)
    }
}

/// 工作项类型字段定义。对应云效 `GetWorkitemTypeFieldConfig` 接口返回的字段配置。
///
/// 关键属性：
/// - `id`：用于 `customFieldValues` 的键；
/// - `format`：字段格式，如 `list`（单选）、`multiList`（多选）等；
/// - `required`：创建工作项时是否必填；
/// - `defaultValue`：默认值，通常为选项 `id`；
/// - `options`：可选值列表，供选择 UI 使用。
public struct YXBFieldDefinition: Identifiable, Sendable, Decodable {
    public let id: String
    public let name: String
    public let description: String?
    public let format: String
    public let type: String
    public let required: Bool
    public let showWhenCreate: Bool
    public let defaultValue: String?
    public let options: [YXBFieldOption]

    private enum CodingKeys: String, CodingKey {
        case id, name, description, format, type, required
        case showWhenCreate, defaultValue, options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        showWhenCreate = try container.decodeIfPresent(Bool.self, forKey: .showWhenCreate) ?? true
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        options = try container.decodeIfPresent([YXBFieldOption].self, forKey: .options) ?? []
    }
}

/// 工作项类型字段列表响应。兼容直接数组 / `data` / `fields` / `items` 等包络。
struct YXBFieldDefinitionsResponse: Decodable {
    let items: [YXBFieldDefinition]

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([YXBFieldDefinition].self) {
            items = array
            return
        }
        let container = try decoder.container(keyedBy: YXBAnyCodingKey.self)
        let candidates = ["data", "fields", "items", "list"]
        for key in candidates {
            if let array = try? container.decode([YXBFieldDefinition].self, forKey: YXBAnyCodingKey(stringValue: key)) {
                items = array
                return
            }
        }
        items = []
    }
}

/// 组织项目模型（云效 `SearchProjects` 接口返回）。公开以便宿主构建「项目」选择器。
///
/// - `id`：项目唯一标识（`identifier`），即工作项接口的 `spaceId` / `projectID`；
/// - `name`：项目名称；
/// - `createdAt`：`gmtCreate` 创建时间戳（毫秒），用于「默认选中最新建立的项目」排序；
/// - `customCode` / `logicalStatus`：辅助信息，可选。
///
/// 注意：`gmtCreate` 在不同接口可能为 `Int`（毫秒）或 `String`，这里做容错解析。
public struct YXBProject: Identifiable, Sendable, Decodable {
    public let id: String
    public let name: String
    public let createdAt: Int64?
    public let customCode: String?
    public let logicalStatus: String?

    private enum CodingKeys: String, CodingKey {
        case id = "identifier"
        case name
        case createdAt = "gmtCreate"
        case customCode
        case logicalStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        customCode = try container.decodeIfPresent(String.self, forKey: .customCode)
        logicalStatus = try container.decodeIfPresent(String.self, forKey: .logicalStatus)
        if let ms = try? container.decode(Int64.self, forKey: .createdAt) {
            createdAt = ms
        } else if let s = try? container.decode(String.self, forKey: .createdAt),
                  !s.isEmpty,
                  let v = Int64(s) {
            createdAt = v
        } else {
            createdAt = nil
        }
    }
}

/// 组织项目列表响应。兼容 直接数组 / `data` / `projects` / `items` / `list` 等多种包络。
struct YXBProjectsResponse: Decodable {
    let items: [YXBProject]

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([YXBProject].self) {
            items = array
            return
        }
        let container = try decoder.container(keyedBy: YXBAnyCodingKey.self)
        let candidates = ["data", "projects", "items", "list"]
        for key in candidates {
            if let array = try? container.decode([YXBProject].self, forKey: YXBAnyCodingKey(stringValue: key)) {
                items = array
                return
            }
        }
        items = []
    }
}

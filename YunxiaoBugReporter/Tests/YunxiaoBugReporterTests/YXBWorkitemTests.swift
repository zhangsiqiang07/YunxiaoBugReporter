import XCTest
@testable import YunxiaoBugReporter

/// 覆盖 `YXBWorkitem` 解码（identifier/id 候选、`subject`、嵌套/字符串 `status`、
/// 嵌套/字符串 `assignedTo`、`gmtCreate` Int/String/空串容错）与 `YXBWorkitemsResponse` 包络容错。
final class YXBWorkitemTests: XCTestCase {

    /// 直接数组 + `identifier` 字段（SearchWorkitems 常见返回）+ 嵌套对象 status/assignedTo + gmtCreate 为 Int（毫秒）。
    func testDirectArrayWithIdentifierAndNestedNames() throws {
        let json = Data(#"""
        [
          {
            "identifier": "WI-1",
            "subject": "崩溃问题",
            "status": {"id":"s1","name":"进行中"},
            "assignedTo": {"id":"u1","name":"张三"},
            "gmtCreate": 1700000000000
          }
        ]
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        let item = try XCTUnwrap(response.items.first)
        XCTAssertEqual(item.id, "WI-1")
        XCTAssertEqual(item.subject, "崩溃问题")
        XCTAssertEqual(item.statusName, "进行中")
        XCTAssertEqual(item.assignedToName, "张三")
        XCTAssertEqual(item.gmtCreate, 1_700_000_000_000)
    }

    /// 兼容使用 `id` 字段作为标识，且 status/assignedTo 以纯字符串形式返回。
    func testIdFieldAndStringStatusAssignee() throws {
        let json = Data(#"""
        [
          {
            "id": "WI-2",
            "subject": "显示异常",
            "status": "打开",
            "assignedTo": "李四",
            "gmtCreate": "1650000000000"
          }
        ]
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        let item = try XCTUnwrap(response.items.first)
        XCTAssertEqual(item.id, "WI-2")
        XCTAssertEqual(item.statusName, "打开")
        XCTAssertEqual(item.assignedToName, "李四")
        XCTAssertEqual(item.gmtCreate, 1_650_000_000_000)
    }

    /// gmtCreate 为空字符串时不应导致解析失败，且 createdAt 为 nil。
    func testEmptyStringGmtCreateYieldsNil() throws {
        let json = Data(#"""
        [
          {
            "identifier": "WI-3",
            "subject": "无创建时间",
            "status": {"name":"待处理"},
            "gmtCreate": ""
          }
        ]
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        let item = try XCTUnwrap(response.items.first)
        XCTAssertEqual(item.id, "WI-3")
        XCTAssertEqual(item.statusName, "待处理")
        XCTAssertNil(item.gmtCreate)
    }

    /// 缺失字段时给出安全默认值：subject 空串、status/assignedTo 为 nil、gmtCreate 为 nil。
    func testMissingFieldsYieldDefaults() throws {
        let json = Data(#"[{"id":"WI-4"}]"#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        let item = try XCTUnwrap(response.items.first)
        XCTAssertEqual(item.id, "WI-4")
        XCTAssertEqual(item.subject, "")
        XCTAssertNil(item.statusName)
        XCTAssertNil(item.assignedToName)
        XCTAssertNil(item.gmtCreate)
    }

    /// 包络为 `{ "data": [...] }` 也能解析。
    func testWrappedDataEnvelope() throws {
        let json = Data(#"""
        {"data":[{"identifier":"WI-5","subject":"S5","gmtCreate":1700000000000}]}
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        XCTAssertEqual(response.items.first?.id, "WI-5")
    }

    /// 包络为 `{ "items": [...] }` 也能解析。
    func testWrappedItemsEnvelope() throws {
        let json = Data(#"""
        {"items":[{"id":"WI-6","subject":"S6"}]}
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        XCTAssertEqual(response.items.first?.id, "WI-6")
    }

    /// 包络为 `{ "workitems": [...] }` 也能解析。
    func testWrappedWorkitemsEnvelope() throws {
        let json = Data(#"""
        {"workitems":[{"id":"WI-7","subject":"S7"}]}
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        XCTAssertEqual(response.items.first?.id, "WI-7")
    }

    /// 显式构造器可用（用于演示/兜底）。
    func testExplicitInitializer() {
        let item = YXBWorkitem(
            id: "WI-x",
            subject: "手动构造",
            statusName: "新建",
            assignedToName: "王五",
            gmtCreate: 1_700_000_000_000
        )
        XCTAssertEqual(item.id, "WI-x")
        XCTAssertEqual(item.subject, "手动构造")
        XCTAssertEqual(item.statusName, "新建")
        XCTAssertEqual(item.assignedToName, "王五")
        XCTAssertEqual(item.gmtCreate, 1_700_000_000_000)
    }

    /// 详情页所需的扩展字段（优先级 / 严重程度 / 创建人 / 所属项目 / 描述 / 更新时间）可容错解码。
    func testEnrichedFieldsDecode() throws {
        let json = Data(#"""
        [
          {
            "identifier": "WI-8",
            "subject": "内存泄漏",
            "status": {"name":"处理中"},
            "assignedTo": {"name":"赵六"},
            "priority": {"name":"P0"},
            "severity": "严重",
            "creator": {"name":"钱七"},
            "space": {"name":"客户端项目"},
            "description": "启动后内存持续增长",
            "gmtCreate": 1700000000000,
            "gmtModified": 1700001000000
          }
        ]
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        let item = try XCTUnwrap(response.items.first)
        XCTAssertEqual(item.id, "WI-8")
        XCTAssertEqual(item.priorityName, "P0")
        XCTAssertEqual(item.severityName, "严重")
        XCTAssertEqual(item.creatorName, "钱七")
        XCTAssertEqual(item.spaceName, "客户端项目")
        XCTAssertEqual(item.description, "启动后内存持续增长")
        XCTAssertEqual(item.gmtModified, 1_700_001_000_000)
    }

    /// 扩展字段缺失时均为 nil（不影响列表接口已返回字段的解析）。
    func testEnrichedFieldsAbsentYieldNil() throws {
        let json = Data(#"[{"id":"WI-9","subject":"S9"}]"#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBWorkitemsResponse.self, from: json)
        let item = try XCTUnwrap(response.items.first)
        XCTAssertNil(item.priorityName)
        XCTAssertNil(item.severityName)
        XCTAssertNil(item.creatorName)
        XCTAssertNil(item.spaceName)
        XCTAssertNil(item.description)
        XCTAssertNil(item.gmtModified)
    }
}

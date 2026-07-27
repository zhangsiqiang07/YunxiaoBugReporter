import XCTest
@testable import YunxiaoBugReporter

/// 覆盖 `YXBProject` 解码（identifier / name / gmtCreate 容错）与 `YXBProjectsResponse` 包络容错。
final class YXBProjectTests: XCTestCase {

    /// 直接数组 + `id` 字段（SearchProjects 真实返回）+ gmtCreate 为 Int（毫秒）。
    func testDirectArrayWithIdField() throws {
        let json = Data(#"""
        [
          {"id":"proj-new","name":"最新项目","gmtCreate":1700000000000,"customCode":"NEWX","logicalStatus":"NORMAL"},
          {"id":"proj-old","name":"旧项目","gmtCreate":1600000000000}
        ]
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBProjectsResponse.self, from: json)
        XCTAssertEqual(response.items.count, 2)

        let newest = response.items.first
        XCTAssertEqual(newest?.id, "proj-new")
        XCTAssertEqual(newest?.name, "最新项目")
        XCTAssertEqual(newest?.createdAt, 1_700_000_000_000)
        XCTAssertEqual(newest?.customCode, "NEWX")
        XCTAssertEqual(newest?.logicalStatus, "NORMAL")

        let oldest = response.items.last
        XCTAssertEqual(oldest?.id, "proj-old")
        XCTAssertEqual(oldest?.createdAt, 1_600_000_000_000)
    }

    /// 兼容部分接口仍使用 `identifier` 作为项目标识。
    func testDirectArrayWithIdentifierField() throws {
        let json = Data(#"""
        [
          {"identifier":"proj-new","name":"最新项目","gmtCreate":1700000000000}
        ]
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBProjectsResponse.self, from: json)
        XCTAssertEqual(response.items.first?.id, "proj-new")
    }

    /// gmtCreate 以字符串形式返回时也应能解析为 Int64；空字符串按 nil 处理。
    func testStringGmtCreateDecodesToCreatedAt() throws {
        let json = Data(#"[{"id":"p1","name":"P1","gmtCreate":"1650000000000"}]"#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBProjectsResponse.self, from: json)
        XCTAssertEqual(response.items.first?.createdAt, 1_650_000_000_000)
    }

    /// 云效官方示例中 gmtCreate 可能为空字符串，不应导致解析失败。
    func testEmptyStringGmtCreateYieldsNil() throws {
        let json = Data(#"""
        [
          {
            "creator":{"id":"u1","name":"user"},
            "customCode":"CCDD",
            "description":"test",
            "gmtCreate":"",
            "gmtModified":"",
            "icon":"xxx",
            "id":"1111",
            "logicalStatus":"normal",
            "modifier":{"id":"u1","name":"user"},
            "name":"project-test",
            "scope":"public",
            "status":{"id":"s1","name":"进行中"}
          }
        ]
        """#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBProjectsResponse.self, from: json)
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.id, "1111")
        XCTAssertEqual(response.items.first?.name, "project-test")
        XCTAssertNil(response.items.first?.createdAt)
    }

    /// 缺失 gmtCreate 时 createdAt 应为 nil，且解析不报错、name 回退为空串。
    func testMissingGmtCreateYieldsNilAndEmptyName() throws {
        let json = Data(#"[{"id":"p2"}]"#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBProjectsResponse.self, from: json)
        let project = try XCTUnwrap(response.items.first)
        XCTAssertEqual(project.id, "p2")
        XCTAssertEqual(project.name, "")
        XCTAssertNil(project.createdAt)
    }

    /// 包络为 `{ "data": [...] }` 也能解析。
    func testWrappedDataEnvelope() throws {
        let json = Data(#"{"data":[{"id":"p3","name":"P3","gmtCreate":1700000000000}]}"#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBProjectsResponse.self, from: json)
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.id, "p3")
    }

    /// 包络为 `{ "projects": [...] }` 也能解析。
    func testWrappedProjectsEnvelope() throws {
        let json = Data(#"{"projects":[{"id":"p4","name":"P4"}]}"#.utf8)
        let response = try YXBJSONCoder.decoder.decode(YXBProjectsResponse.self, from: json)
        XCTAssertEqual(response.items.first?.id, "p4")
    }

    /// 排序：按 createdAt 降序（缺失创建时间的项排在末尾）。
    func testSortingByCreatedAtDescending() async throws {
        let json = Data(#"""
        [
          {"id":"a","name":"A","gmtCreate":100},
          {"id":"b","name":"B"},
          {"id":"c","name":"C","gmtCreate":300}
        ]
        """#.utf8)
        let mock = YXBMockTransport(responses: [(json, 200)])
        let service = YXBWorkitemService(config: YXBTestHelpers.makeConfig(edition: .standard), transport: mock)
        let projects = try await service.fetchOrganizationProjects(token: "t")
        XCTAssertEqual(projects.map { $0.id }, ["c", "a", "b"])
    }
}

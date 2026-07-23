import XCTest
@testable import YunxiaoBugReporter

/// 成员解析测试：锁定云效 projex 成员接口实际返回字段（userId / userName，直接数组包络）。
final class YXBMemberDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    /// 云效 projex 官方 `ListProjectMembers` 返回示例：直接数组，字段为 `userId` / `userName`。
    func testProjexMembersResponseDecodesName() throws {
        let json = """
        [
            { "roleId": "project.admin", "roleName": "管理员", "userAvatar": "xxx",
              "userId": "user-abc", "userName": "张三" },
            { "roleId": "project.member", "roleName": "成员", "userAvatar": "yyy",
              "userId": "user-def", "userName": "李四" }
        ]
        """.data(using: .utf8)!

        let response = try decoder.decode(YXBMembersResponse.self, from: json)
        XCTAssertEqual(response.items.count, 2)

        let first = try XCTUnwrap(response.items.first)
        XCTAssertEqual(first.id, "user-abc", "assignedTo 应使用 userId")
        XCTAssertEqual(first.name, "张三", "负责人选择 UI 应显示 userName，而非 ID")

        let second = try XCTUnwrap(response.items.last)
        XCTAssertEqual(second.id, "user-def")
        XCTAssertEqual(second.name, "李四")
    }

    /// 兼容旧版 `displayName` 字段。
    func testDisplayNameFallback() throws {
        let json = """
        [
            { "identifier": "id-1", "displayName": "王五", "account": "wangwu" }
        ]
        """.data(using: .utf8)!

        let response = try decoder.decode(YXBMembersResponse.self, from: json)
        let member = try XCTUnwrap(response.items.first)
        XCTAssertEqual(member.id, "id-1")
        XCTAssertEqual(member.name, "王五")
    }

    /// 名称缺失时回退为 id，保证 UI 仍可显示可用标识。
    func testNameFallsBackToId() throws {
        let json = """
        [ { "userId": "user-only" } ]
        """.data(using: .utf8)!

        let response = try decoder.decode(YXBMembersResponse.self, from: json)
        let member = try XCTUnwrap(response.items.first)
        XCTAssertEqual(member.id, "user-only")
        XCTAssertEqual(member.name, "user-only")
    }
}

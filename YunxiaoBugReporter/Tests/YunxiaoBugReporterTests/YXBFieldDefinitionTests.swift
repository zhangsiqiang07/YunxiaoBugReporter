import XCTest
@testable import YunxiaoBugReporter

/// 字段定义解析测试：锁定云效 `GetWorkitemTypeFieldConfig` 直接数组包络与字段名。
final class YXBFieldDefinitionTests: XCTestCase {

    private let decoder = JSONDecoder()

    func testDirectArrayDecoding() throws {
        let json = """
        [
            {
                "cascadingOptions": { "mustSelectLeaf": true, "optionsList": [] },
                "defaultValue": "opt-priority-medium",
                "description": "优先级",
                "format": "list",
                "id": "fld-priority",
                "name": "优先级",
                "options": [
                    { "displayValue": "高", "id": "opt-priority-high", "value": "high", "valueEn": "High" },
                    { "displayValue": "中", "id": "opt-priority-medium", "value": "medium", "valueEn": "Medium" },
                    { "displayValue": "低", "id": "opt-priority-low", "value": "low", "valueEn": "Low" }
                ],
                "required": true,
                "showWhenCreate": true,
                "type": "NativeField"
            },
            {
                "defaultValue": "opt-severity-normal",
                "format": "list",
                "id": "fld-severity",
                "name": "严重程度",
                "options": [
                    { "displayValue": "1-致命", "id": "opt-severity-fatal", "value": "1", "valueEn": "1" },
                    { "displayValue": "3-一般", "id": "opt-severity-normal", "value": "3", "valueEn": "3" }
                ],
                "required": true,
                "showWhenCreate": true,
                "type": "CustomField"
            }
        ]
        """.data(using: .utf8)!

        let response = try decoder.decode(YXBFieldDefinitionsResponse.self, from: json)
        XCTAssertEqual(response.items.count, 2)

        let priority = try XCTUnwrap(response.items.first)
        XCTAssertEqual(priority.id, "fld-priority")
        XCTAssertEqual(priority.name, "优先级")
        XCTAssertEqual(priority.format, "list")
        XCTAssertTrue(priority.required)
        XCTAssertEqual(priority.defaultValue, "opt-priority-medium")
        XCTAssertEqual(priority.options.count, 3)
        let medium = try XCTUnwrap(priority.options.first { $0.id == "opt-priority-medium" })
        XCTAssertEqual(medium.displayValue, "中")
        XCTAssertEqual(medium.value, "medium")

        let severity = try XCTUnwrap(response.items.last)
        XCTAssertEqual(severity.name, "严重程度")
        XCTAssertEqual(severity.type, "CustomField")
    }

    func testEmptyArray() throws {
        let json = "[]".data(using: .utf8)!
        let response = try decoder.decode(YXBFieldDefinitionsResponse.self, from: json)
        XCTAssertTrue(response.items.isEmpty)
    }
}

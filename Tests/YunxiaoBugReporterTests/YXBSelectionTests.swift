import XCTest
@testable import YunxiaoBugReporter

/// 覆盖：Bug 类型默认选择规则（8）、无可用类型报错（9）。
final class YXBSelectionTests: XCTestCase {

    private func decodeTypes(_ json: String) throws -> [YXBWorkitemType] {
        let data = Data(json.utf8)
        return try YXBJSONCoder.decoder.decode(YXBWorkitemTypesResponse.self, from: data).items
    }

    func testSelectsDefaultTypeWhenPresent() throws {
        let types = try decodeTypes(
            #"{"data":[{"id":"a","category":"Bug","enabled":true,"default":false},{"id":"b","category":"Bug","enabled":true,"default":true}]}"#
        )
        let selected = try XCTUnwrap(YXBWorkitemTypeSelector.select(from: types))
        XCTAssertEqual(selected.id, "b")
    }

    func testSelectsFirstEnabledWhenNoDefault() throws {
        let types = try decodeTypes(
            #"{"data":[{"id":"a","category":"Bug","enabled":true,"default":false},{"id":"x","category":"Task","enabled":true,"default":true}]}"#
        )
        let selected = try XCTUnwrap(YXBWorkitemTypeSelector.select(from: types))
        XCTAssertEqual(selected.id, "a")
    }

    func testReturnsNilWhenNoUsableBugType() throws {
        let types = try decodeTypes(
            #"{"data":[{"id":"x","category":"Task","enabled":true,"default":true},{"id":"y","category":"Bug","enabled":false,"default":true}]}"#
        )
        XCTAssertNil(YXBWorkitemTypeSelector.select(from: types))
    }

    func testNoAvailableBugTypeThrows() async throws {
        let mock = YXBMockTransport(responses: [(YXBTestHelpers.emptyTypesResponse, 200)])
        let config = YXBTestHelpers.makeConfig(edition: .standard, workitemTypeID: nil)
        let reporter = try YunxiaoBugReporter(configuration: config, transport: mock)
        let report = YXBBugReport(title: "t", description: "d")
        do {
            _ = try await reporter.submit(report)
            XCTFail("应抛出 workitemTypeNotFound")
        } catch YXBError.workitemTypeNotFound {
            // 期望
        } catch {
            XCTFail("错误类型不符: \(error)")
        }
        let recorded = mock.recordedRequests
        let urls = recorded.map { $0.url?.absoluteString ?? "" }
        XCTAssertTrue(urls.contains { $0.contains("/workitemTypes") }, "应发起工作项类型查询")
    }
}

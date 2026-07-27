import Foundation
@testable import YunxiaoBugReporter

/// 测试配置与样本响应助手。
enum YXBTestHelpers {
    static func makeConfig(
        edition: YXBConfiguration.Edition,
        organizationID: String? = "org-1",
        projectID: String = "proj-1",
        workitemTypeID: String? = "wt-1",
        assignedTo: String = "user-1",
        token: String = "test-token",
        logger: (any YXBLogger)? = nil
    ) -> YXBConfiguration {
        YXBConfiguration(
            domain: "https://yx.example.com",
            edition: edition,
            organizationID: organizationID,
            projectID: projectID,
            workitemTypeID: workitemTypeID,
            assignedTo: assignedTo,
            tokenProvider: { token },
            logger: logger
        )
    }

    static let typesResponse = Data(
        #"{"data":[{"id":"wt-default","name":"默认Bug","category":"Bug","enabled":true,"default":true},{"id":"wt-other","name":"其它Bug","category":"Bug","enabled":true,"default":false}]}"#.utf8
    )

    static let emptyTypesResponse = Data(#"{"data":[]}"#.utf8)
    static let createResponse = Data(#"{"id":"WI-123"}"#.utf8)

    static func attachmentResponse(id: String) -> Data {
        Data(#"{"id":"\#(id)"}"#.utf8)
    }

    static func jsonBody(of request: URLRequest) -> [String: Any]? {
        guard let body = request.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}

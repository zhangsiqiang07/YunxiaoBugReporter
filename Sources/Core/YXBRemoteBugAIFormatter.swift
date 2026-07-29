import Foundation

/// 调用 Bug AI 服务所需的客户端输入。仅包含用户描述与脱敏后的上下文，
/// 不包含截图、网络请求正文、云效 Token 或任何模型凭据。
public struct YXBBugAIGenerateRequest: Encodable, Sendable {
    public struct Page: Encodable, Sendable {
        public let name: String?
        public let route: String?

        public init(name: String?, route: String?) {
            self.name = name
            self.route = route
        }
    }

    public struct Environment: Encodable, Sendable {
        public let appVersion: String?
        public let build: String?
        public let device: String?
        public let osVersion: String?
        public let network: String?

        enum CodingKeys: String, CodingKey {
            case appVersion = "app_version"
            case build, device
            case osVersion = "os_version"
            case network
        }

        public init(appVersion: String?, build: String?, device: String?, osVersion: String?, network: String?) {
            self.appVersion = appVersion
            self.build = build
            self.device = device
            self.osVersion = osVersion
            self.network = network
        }
    }

    public let description: String
    public let issueType: String?
    public let severity: String?
    public let frequency: String?
    public let page: Page?
    public let recentActions: [String]
    public let environment: Environment?
    /// 宿主自定义、已脱敏的补充上下文；服务端以既有 `extra` 字段接收。
    public let extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case description
        case issueType = "issue_type"
        case severity, frequency, page
        case recentActions = "recent_actions"
        case environment, extra
    }

    public init(
        description: String,
        issueType: String?,
        severity: String?,
        frequency: String?,
        page: Page?,
        recentActions: [String],
        environment: Environment?,
        extra: [String: String] = [:]
    ) {
        self.description = description
        self.issueType = issueType
        self.severity = severity
        self.frequency = frequency
        self.page = page
        self.recentActions = recentActions
        self.environment = environment
        self.extra = extra
    }
}

/// Bug AI 服务校验后的结构化结果。
public struct YXBBugAIGeneratedReport: Decodable, Sendable {
    public let title: String
    public let actualResult: String
    public let expectedResult: String?
    public let expectedResultInferred: Bool
    public let reproductionSteps: [String]
    public let module: String?
    public let issueType: String?
    public let severity: String
    public let frequency: String
    public let missingInformation: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case actualResult = "actual_result"
        case expectedResult = "expected_result"
        case expectedResultInferred = "expected_result_inferred"
        case reproductionSteps = "reproduction_steps"
        case module, severity, frequency
        case issueType = "issue_type"
        case missingInformation = "missing_information"
    }
}

/// Bug AI 服务的网络调用错误。错误信息不包含请求正文或密钥。
public enum YXBBugAIServiceError: Error, Sendable {
    case invalidServiceDomain
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case decodingFailed
}

extension YXBBugAIServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidServiceDomain:
            return "Bug AI 服务域名无效，请配置 http 或 https 地址。"
        case .invalidResponse:
            return "Bug AI 服务返回了无效响应。"
        case .requestFailed(let statusCode, let message):
            return "Bug AI 服务请求失败（HTTP \(statusCode)）\(message.map { "：\($0)" } ?? "")"
        case .decodingFailed:
            return "Bug AI 服务返回格式无效。"
        }
    }
}

/// 基于 SDK 外部注入域名的 Bug AI 服务客户端。
public final class YXBRemoteBugAIFormatter: @unchecked Sendable {
    private struct Response: Decodable {
        let data: YXBBugAIGeneratedReport
    }

    private struct ErrorResponse: Decodable {
        let detail: String?
    }

    private let endpoint: URL
    private let session: URLSession

    /// - Parameter serviceDomain: 服务根地址，不含 `/api/v1/bug-report/generate` 路径。
    public init(serviceDomain: String, timeout: TimeInterval = 180) throws {
        self.endpoint = try Self.makeEndpoint(serviceDomain: serviceDomain)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: configuration)
    }

    public func generate(_ payload: YXBBugAIGenerateRequest) async throws -> YXBBugAIGeneratedReport {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YXBBugAIServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).detail
            throw YXBBugAIServiceError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw YXBBugAIServiceError.decodingFailed
        }
        return decoded.data
    }

    static func makeEndpoint(serviceDomain: String) throws -> URL {
        let trimmed = serviceDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              components.query == nil,
              components.fragment == nil else {
            throw YXBBugAIServiceError.invalidServiceDomain
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "api/v1/bug-report/generate"]
            .filter { !$0.isEmpty }
            .joined(separator: "/"))
        guard let endpoint = components.url else {
            throw YXBBugAIServiceError.invalidServiceDomain
        }
        return endpoint
    }
}

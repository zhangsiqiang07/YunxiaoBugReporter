import Foundation

/// 请求构造器。负责把 endpoint、config、token、body 组合成 `URLRequest`，
/// 并统一注入 `x-yunxiao-token` 头。
struct YXBRequestBuilder {
    /// 通用构造方法。
    /// - Parameters:
    ///   - endpoint: 端点。
    ///   - config: 配置（提供 domain、projectID 等）。
    ///   - method: HTTP 方法。
    ///   - token: 通过 `x-yunxiao-token` 头传递的令牌（不写入日志）。
    ///   - query: 查询参数。
    ///   - body: 请求体（有值时设置 Content-Type / Content-Length）。
    ///   - contentType: 自定义 Content-Type（multipart 时使用）。
    func build(
        endpoint: YXBEndpoint,
        config: YXBConfiguration,
        method: String,
        token: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil
    ) throws -> URLRequest {
        guard let baseURL = URL(string: config.domain),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw YXBError.invalidConfiguration("domain 不是合法 URL: \(config.domain)")
        }

        var path = components.path
        if !path.hasSuffix("/") { path += "/" }
        let ep = endpoint.path(config: config)
        let epTrimmed = ep.hasPrefix("/") ? String(ep.dropFirst()) : ep
        path += epTrimmed
        components.path = path

        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }

        guard let url = components.url else {
            throw YXBError.invalidConfiguration("无法根据 domain 与路径构造请求 URL。")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        // 统一注入令牌头。
        request.setValue(token, forHTTPHeaderField: "x-yunxiao-token")

        if let body = body {
            request.httpBody = body
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        return request
    }

    /// 构造 JSON 请求体请求（application/json）。
    func buildJSON(
        endpoint: YXBEndpoint,
        config: YXBConfiguration,
        token: String,
        method: String = "POST",
        body: Data
    ) throws -> URLRequest {
        try build(endpoint: endpoint, config: config, method: method, token: token, body: body, contentType: "application/json")
    }

    /// 构造 multipart/form-data 请求（正确使用 boundary 与 Content-Length）。
    func buildMultipart(
        endpoint: YXBEndpoint,
        config: YXBConfiguration,
        token: String,
        boundary: String,
        body: Data
    ) throws -> URLRequest {
        try build(
            endpoint: endpoint,
            config: config,
            method: "POST",
            token: token,
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }
}

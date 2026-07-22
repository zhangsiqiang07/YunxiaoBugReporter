import Foundation
@testable import YunxiaoBugReporter

/// 可注入的 Mock 传输层（测试用）。
///
/// - 记录所有发出的请求（`recordedRequests`）供断言；
/// - 支持两种模式：固定响应队列，或基于请求的自定义 `handler`；
/// - 非 2xx 响应抛出 `YXBError.httpError`，与真实 `YXBHTTPClient` 行为一致。
///
/// 使用串行 `DispatchQueue` 保护可变状态（兼容 iOS 15 部署目标，且可在 `async` 上下文中安全调用），
/// 避免并发上传时的数据竞争，也规避 `NSLock` 在 async 上下文的 Swift 6 严格并发告警。
final class YXBMockTransport: YXBTransport {
    private let syncQueue = DispatchQueue(label: "com.yunxiao.mock.transport")
    private var recorded: [URLRequest] = []
    private var queue: [(Data, Int)] = []
    private var handler: (@Sendable (URLRequest) -> (Data, Int))?
    private var cursor = 0

    init(responses: [(Data, Int)]) {
        self.queue = responses
    }

    init(handler: @escaping @Sendable (URLRequest) -> (Data, Int)) {
        self.handler = handler
    }

    var recordedRequests: [URLRequest] {
        syncQueue.sync { recorded }
    }

    func send<T: Decodable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        let (data, status) = syncQueue.sync { () -> (Data, Int) in
            recorded.append(request)
            return next(request)
        }
        try validate(status: status, data: data)
        return try YXBJSONCoder.decoder.decode(T.self, from: data)
    }

    func sendWithoutResponse(_ request: URLRequest) async throws {
        let (data, status) = syncQueue.sync { () -> (Data, Int) in
            recorded.append(request)
            return next(request)
        }
        try validate(status: status, data: data)
    }

    /// 调用方须持有 `syncQueue`。
    private func next(_ request: URLRequest) -> (Data, Int) {
        if let handler = handler {
            return handler(request)
        }
        guard !queue.isEmpty else { return (Data(), 200) }
        let item = queue[min(cursor, queue.count - 1)]
        if cursor < queue.count - 1 { cursor += 1 }
        return item
    }

    private func validate(status: Int, data: Data) throws {
        guard (200..<300).contains(status) else {
            let parsed = YXBErrorParser.parse(data: data, statusCode: status)
            throw YXBError.httpError(statusCode: status, message: parsed.message)
        }
    }
}

extension YXBMockTransport: @unchecked Sendable {}

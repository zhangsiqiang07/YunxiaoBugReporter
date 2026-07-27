import Foundation
@testable import YunxiaoBugReporter

/// 记录所有日志消息的 Logger，用于断言敏感信息（如 Token）未被输出。
///
/// 使用串行 `DispatchQueue` 保护可变状态（兼容 iOS 15 部署目标，且可在 `async` 上下文中安全调用），
/// 使其满足 `Sendable`，可在并发上下文中安全使用。
final class YXBRecordingLogger: YXBLogger {
    private let syncQueue = DispatchQueue(label: "com.yunxiao.mock.logger")
    private var backingMessages: [String] = []
    private var backingLevels: [YXBLogLevel] = []

    var messages: [String] {
        syncQueue.sync { backingMessages }
    }

    var levels: [YXBLogLevel] {
        syncQueue.sync { backingLevels }
    }

    func log(level: YXBLogLevel, message: String) {
        syncQueue.sync {
            backingMessages.append(message)
            backingLevels.append(level)
        }
    }

    func contains(_ substring: String) -> Bool {
        syncQueue.sync { backingMessages.contains { $0.contains(substring) } }
    }
}

extension YXBRecordingLogger: @unchecked Sendable {}

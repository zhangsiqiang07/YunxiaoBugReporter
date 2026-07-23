import Foundation

/// 空日志器：用于显式关闭 SDK 的日志输出。
///
/// 用法：
/// ```swift
/// var config = YXBConfiguration(...)
/// config.logger = YXBNoOpLogger()
/// ```
public struct YXBNoOpLogger: YXBLogger {
    public init() {}

    public func log(level: YXBLogLevel, message: String) {
        // 故意不输出任何内容。
    }
}

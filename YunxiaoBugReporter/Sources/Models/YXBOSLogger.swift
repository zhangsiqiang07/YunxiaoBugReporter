import Foundation
import os

/// 基于 `os.log` 的内置日志器。
///
/// 作为 SDK 的默认日志实现：当 `YXBConfiguration.logger` 为 `nil` 时，
/// 传输层会自动使用本日志器，确保「所有请求都有日志」。
///
/// 示例（系统日志 / Xcode 控制台可见）：
/// ```
/// [YunxiaoBugReporter] → POST https://yunxiao.example.com/oapi/v1/projex/.../workitems
/// [YunxiaoBugReporter] ← 201 https://yunxiao.example.com/... (0.34s, 512 bytes)
/// ```
public struct YXBOSLogger: YXBLogger {
    /// 共享单例，供默认日志使用。
    public static let shared = YXBOSLogger()

    private let log: OSLog

    /// 自定义子系统与分类。
    /// - Parameters:
    ///   - subsystem: 子系统标识，默认 `com.yunxiao.bugreporter`。
    ///   - category: 日志分类，默认 `YunxiaoBugReporter`。
    public init(subsystem: String = "com.yunxiao.bugreporter", category: String = "YunxiaoBugReporter") {
        self.log = OSLog(subsystem: subsystem, category: category)
    }

    public func log(level: YXBLogLevel, message: String) {
        let type: OSLogType
        switch level {
        case .debug: type = .debug
        case .info:  type = .info
        case .warn:  type = .default
        case .error: type = .error
        }
        os_log("%{public}@", log: log, type: type, message)
    }
}

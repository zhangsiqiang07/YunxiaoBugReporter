import Foundation

/// 日志级别。SDK 仅负责分级调用，是否输出由宿主提供的 `YXBLogger` 决定。
public enum YXBLogLevel: Int, Sendable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3
}

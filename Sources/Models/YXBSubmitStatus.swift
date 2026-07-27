import Foundation

/// 整体提交状态。
public enum YXBSubmitStatus: Sendable {
    /// 工作项与全部附件均成功。
    case success
    /// 工作项创建成功，但部分附件失败。SDK 不会因此抛错，而是返回此状态。
    case partialSuccess
}

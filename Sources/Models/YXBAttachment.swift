import Foundation

/// 待上传的附件。
///
/// SDK 不依赖 UIKit，仅接收 `Data`。宿主负责把图片、日志或任意文件转为 `Data` 后传入。
public struct YXBAttachment: Sendable {
    /// 附件二进制内容。
    public let data: Data
    /// 文件名（用于 multipart 的 `filename`）。
    public let fileName: String
    /// MIME 类型（用于 multipart 的 `Content-Type`）。
    public let mimeType: String

    public init(data: Data, fileName: String, mimeType: String) {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

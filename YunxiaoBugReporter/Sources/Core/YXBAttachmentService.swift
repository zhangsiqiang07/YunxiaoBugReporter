import Foundation

/// 附件服务：以 multipart/form-data 上传附件，支持有限并发。
struct YXBAttachmentService {
    let config: YXBConfiguration
    let transport: any YXBTransport
    private let builder: YXBRequestBuilder

    init(config: YXBConfiguration, transport: any YXBTransport) {
        self.config = config
        self.transport = transport
        self.builder = YXBRequestBuilder()
    }

    /// 上传全部附件。
    ///
    /// - 并发数由 `config.maximumConcurrentUploads`（1...4）控制，按批次处理；
    /// - 返回结果顺序与输入 `attachments` 顺序一致；
    /// - 单个附件失败只会影响自身结果，不会取消或影响其他附件；
    /// - 调用方保证工作项已创建成功。
    func uploadAll(_ attachments: [YXBAttachment], workitemID: String, token: String) async -> [YXBAttachmentResult] {
        guard !attachments.isEmpty else { return [] }

        var results = Array<YXBAttachmentResult?>(repeating: nil, count: attachments.count)
        let batchSize = max(1, min(config.maximumConcurrentUploads, YXBConstants.maxConcurrentUploadsCap))

        for batchStart in stride(from: 0, to: attachments.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, attachments.count)
            await withTaskGroup(of: (Int, YXBAttachmentResult).self) { group in
                for index in batchStart..<batchEnd {
                    group.addTask {
                        let result = await self.uploadOne(attachments[index], index: index, workitemID: workitemID, token: token)
                        return (index, result)
                    }
                }
                for await (index, result) in group {
                    results[index] = result
                }
            }
        }

        return results.compactMap { $0 }
    }

    /// 上传单个附件。任何异常都会被捕获并转换为失败的 `YXBAttachmentResult`，不向上抛出。
    private func uploadOne(_ attachment: YXBAttachment, index: Int, workitemID: String, token: String) async -> YXBAttachmentResult {
        do {
            try YXBValidation.validateAttachment(attachment, maxBytes: YXBConstants.maxAttachmentBytes)
            let (body, boundary) = YXBMultipartBuilder.build(attachment: attachment)
            let request = try builder.buildMultipart(
                endpoint: .attachments(workitemId: workitemID),
                config: config,
                token: token,
                boundary: boundary,
                body: body
            )
            let response: YXBAttachmentCreateResponse = try await transport.send(request, responseType: YXBAttachmentCreateResponse.self)
            return YXBAttachmentResult(fileName: attachment.fileName, success: true, attachmentID: response.id)
        } catch {
            let yxb: YXBError = (error as? YXBError) ?? .underlying(String(describing: error))
            return YXBAttachmentResult(fileName: attachment.fileName, success: false, attachmentID: nil, error: yxb)
        }
    }
}

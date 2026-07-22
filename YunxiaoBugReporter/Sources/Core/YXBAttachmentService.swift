import Foundation

/// 附件服务：以 multipart/form-data 上传附件，支持有限并发。
struct YXBAttachmentService: Sendable {
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

        // 将 Sendable 成员提升为局部常量，避免任务组闭包捕获 `self`，
        // 从而消除 Swift 6 下隐式 isolation() 捕获带来的可用性报错。
        let config = self.config
        let transport = self.transport
        let builder = self.builder

        var results = Array<YXBAttachmentResult?>(repeating: nil, count: attachments.count)
        let batchSize = max(1, min(config.maximumConcurrentUploads, YXBConstants.maxConcurrentUploadsCap))

        for batchStart in stride(from: 0, to: attachments.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, attachments.count)
            await withTaskGroup(of: (Int, YXBAttachmentResult).self, isolation: nil) { group in
                for index in batchStart..<batchEnd {
                    let attachment = attachments[index]
                    group.addTask {
                        let result = await Self.uploadOne(
                            attachment: attachment,
                            index: index,
                            workitemID: workitemID,
                            token: token,
                            config: config,
                            transport: transport,
                            builder: builder
                        )
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
    private static func uploadOne(
        attachment: YXBAttachment,
        index: Int,
        workitemID: String,
        token: String,
        config: YXBConfiguration,
        transport: any YXBTransport,
        builder: YXBRequestBuilder
    ) async -> YXBAttachmentResult {
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

import XCTest
@testable import YunxiaoBugReporter

/// 覆盖附件上传响应解码（嵌入片段字段）与 `YXBDescriptionEmbedder` 的描述嵌入逻辑。
final class YXBAttachmentTests: XCTestCase {

    /// 上传附件响应包含 `embedHtml` / `embedMarkdown` / `embedUrl` / `url` / `name`。
    func testAttachmentCreateResponseDecodesEmbedFields() throws {
        let json = Data(#"""
        {
          "id": "att-1",
          "name": "shot.png",
          "embedHtml": "<img src=\"https://x.test/embed/1\" />",
          "embedMarkdown": "![](https://x.test/embed/1)",
          "embedUrl": "https://x.test/embed/1",
          "url": "https://x.test/tmp/1"
        }
        """#.utf8)
        let resp = try YXBJSONCoder.decoder.decode(YXBAttachmentCreateResponse.self, from: json)
        XCTAssertEqual(resp.id, "att-1")
        XCTAssertEqual(resp.name, "shot.png")
        XCTAssertEqual(resp.embedHTML, "<img src=\"https://x.test/embed/1\" />")
        XCTAssertEqual(resp.embedMarkdown, "![](https://x.test/embed/1)")
        XCTAssertEqual(resp.embedURL, "https://x.test/embed/1")
        XCTAssertEqual(resp.url, "https://x.test/tmp/1")
    }

    /// 缺失嵌入字段时不报错，对应项为 nil。
    func testAttachmentCreateResponseToleratesMissingEmbedFields() throws {
        let json = Data(#"{"id":"att-2"}"#.utf8)
        let resp = try YXBJSONCoder.decoder.decode(YXBAttachmentCreateResponse.self, from: json)
        XCTAssertEqual(resp.id, "att-2")
        XCTAssertNil(resp.embedHTML)
        XCTAssertNil(resp.embedMarkdown)
        XCTAssertNil(resp.embedURL)
        XCTAssertNil(resp.url)
    }

    /// RICHTEXT 模式优先使用 `embedHtml`。
    func testDescriptionEmbedderEmbedsRichTextImages() {
        let results = [
            YXBAttachmentResult(fileName: "a.png", success: true, embedHTML: "<img src=\"https://x/1\" />"),
            YXBAttachmentResult(fileName: "b.png", success: true, embedMarkdown: "![](https://x/2)")
        ]
        let embedded = YXBDescriptionEmbedder.embed(attachments: results, format: .plainText, into: "hello")
        XCTAssertEqual(embedded, "hello\n<img src=\"https://x/1\" />")
    }

    /// MARKDOWN 模式优先使用 `embedMarkdown`。
    func testDescriptionEmbedderEmbedsMarkdownImages() {
        let results = [
            YXBAttachmentResult(fileName: "a.png", success: true, embedHTML: "<img src=\"https://x/1\" />", embedMarkdown: "![](https://x/1)")
        ]
        let embedded = YXBDescriptionEmbedder.embed(attachments: results, format: .markdown, into: "")
        XCTAssertEqual(embedded, "![](https://x/1)")
    }

    /// 没有现成片段时，RICHTEXT / MARKDOWN 各自回退到 `embedUrl` 拼接。
    func testDescriptionEmbedderFallsBackToEmbedURL() {
        let results = [YXBAttachmentResult(fileName: "a.png", success: true, embedURL: "https://x/1")]
        XCTAssertEqual(
            YXBDescriptionEmbedder.embed(attachments: results, format: .plainText, into: "d"),
            "d\n<img src=\"https://x/1\" />"
        )
        XCTAssertEqual(
            YXBDescriptionEmbedder.embed(attachments: results, format: .markdown, into: "d"),
            "d\n![image](https://x/1)"
        )
    }

    /// 没有可嵌入片段（全部失败 / 非图片）时返回 nil，调用方据此跳过描述更新。
    func testDescriptionEmbedderReturnsNilWhenNothingEmbeddable() {
        let failed = [YXBAttachmentResult(fileName: "a.png", success: false, error: .underlying("x"))]
        XCTAssertNil(YXBDescriptionEmbedder.embed(attachments: failed, format: .plainText, into: "d"))
        let noSnippet = [YXBAttachmentResult(fileName: "a.txt", success: true)]
        XCTAssertNil(YXBDescriptionEmbedder.embed(attachments: noSnippet, format: .plainText, into: "d"))
    }
}

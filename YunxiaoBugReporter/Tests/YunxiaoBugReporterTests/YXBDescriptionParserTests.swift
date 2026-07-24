import XCTest
@testable import YunxiaoBugReporter

/// 覆盖 `YXBDescriptionParser` 对三种描述格式的解析：
/// 1. JSON 结构化描述（htmlValue + jsonMLValue）；
/// 2. 普通 HTML 字符串；
/// 3. Markdown 字符串。
final class YXBDescriptionParserTests: XCTestCase {

    /// 与截图一致的结构化 JSON 描述：htmlValue 为 `&nbsp;`，正文在 jsonMLValue 的图片节点中。
    func testJSONMLDescriptionExtractsImagesAndSkipsRawJSON() {
        let json = #"""
        {"htmlValue":"&nbsp;","jsonMLValue":["root",{},["p",{},["span",{"data-type":"text"},["span",{"data-type":"leaf"},["img",{"id":"a1","name":"image1.png","src":"https://devops.aliyun.com/projex/api/workitem/file/url?fileIdentifier=abc-1"},"/"]],["span",{"data-type":"text"},["span",{"data-type":"leaf"},["img",{"id":"a2","name":"image2.png","src":"https://devops.aliyun.com/projex/api/workitem/file/url?fileIdentifier=abc-2"},"/"]]]]}
        """#

        let result = YXBDescriptionParser.parse(json)

        XCTAssertEqual(result.imageURLs.count, 2)
        XCTAssertEqual(result.imageURLs[0].absoluteString, "https://devops.aliyun.com/projex/api/workitem/file/url?fileIdentifier=abc-1")
        XCTAssertEqual(result.imageURLs[1].absoluteString, "https://devops.aliyun.com/projex/api/workitem/file/url?fileIdentifier=abc-2")
        // 不应把原始 JSON 当作文本展示。
        XCTAssertFalse(result.text.contains("jsonMLValue"))
        XCTAssertFalse(result.text.contains("htmlValue"))
        XCTAssertFalse(result.text.contains("img"))
    }

    /// jsonML 中同时含文本与图片时，应保留文本并抽图。
    func testJSONMLMixedTextAndImages() {
        let json = #"""
        {"jsonMLValue":["root",{},["p",{},"Hello ",["b",{},"World"],["img",{"src":"https://x/pic.png"}],"!"]]}
        """#

        let result = YXBDescriptionParser.parse(json)

        XCTAssertEqual(result.text, "Hello World!")
        XCTAssertEqual(result.imageURLs.count, 1)
        XCTAssertEqual(result.imageURLs.first?.absoluteString, "https://x/pic.png")
    }

    /// JSON 描述只有 htmlValue 且为有效 HTML 时，按 HTML 解析。
    func testJSONHTMLValueFallback() {
        let json = #"""
        {"htmlValue":"<p>See <img src=\"https://x/a.png\"></p>"}
        """#

        let result = YXBDescriptionParser.parse(json)

        XCTAssertEqual(result.text, "See")
        XCTAssertEqual(result.imageURLs.count, 1)
        XCTAssertEqual(result.imageURLs.first?.absoluteString, "https://x/a.png")
    }

    /// 普通 HTML 字符串。
    func testPlainHTMLDescription() {
        let html = "<p>正文</p><img src=\"https://x/1.png\"/><br><img src=\"https://x/2.png\">"

        let result = YXBDescriptionParser.parse(html)

        XCTAssertEqual(result.text, "正文")
        XCTAssertEqual(result.imageURLs.count, 2)
    }

    /// Markdown 图片语法。
    func testMarkdownImageDescription() {
        let md = "截图如下：![截图](https://x/shot.png) 请查看"

        let result = YXBDescriptionParser.parse(md)

        XCTAssertEqual(result.text, "截图如下： 请查看")
        XCTAssertEqual(result.imageURLs.count, 1)
        XCTAssertEqual(result.imageURLs.first?.absoluteString, "https://x/shot.png")
    }

    /// 空或 nil 描述返回空结果。
    func testEmptyDescription() {
        XCTAssertEqual(YXBDescriptionParser.parse(nil).text, "")
        XCTAssertEqual(YXBDescriptionParser.parse(nil).imageURLs.count, 0)
        XCTAssertEqual(YXBDescriptionParser.parse("").text, "")
        XCTAssertEqual(YXBDescriptionParser.parse("   ").imageURLs.count, 0)
    }
}

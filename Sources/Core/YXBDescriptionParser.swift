import Foundation

/// 云效工作项描述的解析器。
///
/// 云效「描述」字段在不同接口 / 格式下可能返回多种形式：
/// 1. JSON 结构化描述：`{"htmlValue":"...","jsonMLValue":["root",{},[...]]}`。
///    其中 `jsonMLValue` 是 jsonML 树，图片以 `["img", {"src":"..."}]` 节点存在。
/// 2. 普通 HTML 字符串：`<p>...<img src="...">...</p>`。
/// 3. Markdown 字符串：`![alt](url)`。
///
/// 该解析器统一提取可展示的正文文本和图片 URL。
public struct YXBDescriptionParser: Sendable {
    public struct Result: Sendable {
        /// 剔除图片标签后的正文文本（已解码常见 HTML 实体并规范化空白）。
        public let text: String
        /// 描述中包含的图片地址。
        public let imageURLs: [URL]

        public init(text: String, imageURLs: [URL]) {
            self.text = text
            self.imageURLs = imageURLs
        }
    }

    /// 解析描述字符串，返回正文与图片 URL。
    public static func parse(_ description: String?) -> Result {
        guard let description, !description.isEmpty else {
            return Result(text: "", imageURLs: [])
        }

        // 1) JSON 结构化描述：优先 jsonMLValue，其次 htmlValue。
        if let data = description.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let jsonMLValue = json["jsonMLValue"] {
                let rawText = extractText(from: jsonMLValue)
                let urls = extractImageURLs(from: jsonMLValue)
                return Result(text: cleanText(rawText), imageURLs: urls)
            }
            if let htmlValue = json["htmlValue"] as? String, !htmlValue.isEmpty {
                return parseHTMLLike(htmlValue)
            }
        }

        // 2) 普通 HTML / Markdown。
        return parseHTMLLike(description)
    }

    // MARK: - jsonML 解析

    /// 从 jsonML 节点递归提取文本。
    private static func extractText(from value: Any) -> String {
        if let string = value as? String {
            // jsonML 自关闭标记（如 img 后的 "/"）不视为正文。
            return string == "/" ? "" : string
        }

        guard let array = value as? [Any] else { return "" }
        guard let tag = array.first as? String else { return "" }

        // 跳过不贡献正文的标签。
        if ["img", "br", "hr", "input"].contains(tag) {
            return ""
        }

        // jsonML 元素格式：[tagName, attributes?, child1, child2, ...]
        // 若第二个元素不是字典，则它本身就是子节点。
        let children: [Any]
        if array.count >= 2, array[1] is [String: Any] {
            children = Array(array.dropFirst(2))
        } else {
            children = Array(array.dropFirst(1))
        }

        let joined = children.map { extractText(from: $0) }.joined()

        // 块级元素后追加换行，使纯文本更具可读性。
        let blockTags = Set(["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote"])
        if blockTags.contains(tag), !joined.isEmpty {
            return joined + "\n"
        }
        return joined
    }

    /// 从 jsonML 节点递归提取图片 URL。
    private static func extractImageURLs(from value: Any) -> [URL] {
        var urls: [URL] = []

        guard let array = value as? [Any], let tag = array.first as? String else {
            return urls
        }

        if tag == "img" || tag == "image" {
            let attrs: [String: Any]
            if array.count >= 2, let dict = array[1] as? [String: Any] {
                attrs = dict
            } else {
                attrs = [:]
            }
            if let src = attrs["src"] as? String,
               let url = URL(string: src) {
                urls.append(url)
            }
        }

        let children: [Any]
        if array.count >= 2, array[1] is [String: Any] {
            children = Array(array.dropFirst(2))
        } else {
            children = Array(array.dropFirst(1))
        }
        for child in children {
            urls.append(contentsOf: extractImageURLs(from: child))
        }
        return urls
    }

    // MARK: - HTML / Markdown 解析

    private static func parseHTMLLike(_ text: String) -> Result {
        let urls = extractImageURLsFromHTMLAndMarkdown(text)
        let body = textWithoutImages(text)
        return Result(text: body, imageURLs: urls)
    }

    private static func extractImageURLsFromHTMLAndMarkdown(_ text: String) -> [URL] {
        var urls: [URL] = []

        let htmlPattern = #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: htmlPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text),
                   let url = URL(string: String(text[r])) {
                    urls.append(url)
                }
            }
        }

        let mdPattern = #"!\[[^\]]*\]\(([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: mdPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text),
                   let url = URL(string: String(text[r])) {
                    urls.append(url)
                }
            }
        }

        return urls
    }

    private static func textWithoutImages(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        if let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^)]+\)"#, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        if let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return cleanText(result)
    }

    // MARK: - 文本清理

    private static func cleanText(_ text: String) -> String {
        var result = text

        // 解码常见 HTML 实体。
        let entities: [String: String] = [
            "&nbsp;": " ",
            "&lt;": "<",
            "&gt;": ">",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // 合并连续水平空白为单个空格，但保留换行。
        result = result.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        // 合并 3 个及以上连续换行为两个换行。
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

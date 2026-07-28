import Foundation

/// 生成提交到云效的 Markdown 描述。
///
/// 网络轨迹会附带请求体与响应体，方便在云效工作项中定位问题。
/// Header 不写入描述；Body 由宿主在注入前脱敏，并使用动态 Markdown 围栏安全包裹。
enum YXBDescriptionComposer {
    private static let maximumNetworkSummaries = 8
    private static let maximumSummaryTextLength = 240
    private static let maximumBodyLength = 12_000

    static func compose(body: String, context: YXBBugContext) -> String {
        var parts: [String] = []

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            parts.append(trimmedBody)
        }

        parts.append("## 环境信息\n" + context.descriptionLines.joined(separator: "\n"))

        if !context.recentRequests.isEmpty {
            let requests = context.recentRequests.prefix(maximumNetworkSummaries)
            var sections = requests.map(networkDetail)
            let omittedCount = context.recentRequests.count - requests.count
            if omittedCount > 0 {
                sections.append("- 其余 \(omittedCount) 条网络请求未附带")
            }
            parts.append("## 最近网络请求\n" + sections.joined(separator: "\n\n---\n\n"))
        }

        return parts.joined(separator: "\n\n")
    }

    static func networkSummary(_ breadcrumb: YXBNetworkBreadcrumb, prefix: String = "- ") -> String {
        var summary = "\(prefix)\(compact(pathWithoutQuery(breadcrumb.path)))"
        summary += " · \(breadcrumb.statusCode.map(String.init) ?? "无状态码")"
        summary += " · \(breadcrumb.durationMs)ms"
        if let error = breadcrumb.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            summary += " · 错误：\(compact(error))"
        }
        return summary
    }

    private static func networkDetail(_ breadcrumb: YXBNetworkBreadcrumb) -> String {
        var sections = [networkSummary(breadcrumb)]
        if let requestBody = nonEmpty(breadcrumb.requestBody) {
            sections.append("请求体\n" + fencedCodeBlock(requestBody))
        }
        if let responseBody = nonEmpty(breadcrumb.responseBody) {
            sections.append("响应体\n" + fencedCodeBlock(responseBody))
        }
        return sections.joined(separator: "\n")
    }

    private static func pathWithoutQuery(_ path: String) -> String {
        String(path.prefix(while: { $0 != "?" && $0 != "#" }))
    }

    private static func compact(_ value: String) -> String {
        let singleLine = value
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        guard singleLine.count > maximumSummaryTextLength else { return singleLine }
        return String(singleLine.prefix(maximumSummaryTextLength)) + "…"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func fencedCodeBlock(_ body: String) -> String {
        let content: String
        if body.count > maximumBodyLength {
            content = String(body.prefix(maximumBodyLength)) + "\n\n[内容过长，已截断]"
        } else {
            content = body
        }
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: content) + 1))
        return "\(fence)text\n\(content)\n\(fence)"
    }

    private static func longestBacktickRun(in value: String) -> Int {
        var longest = 0
        var current = 0
        for character in value {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }
}

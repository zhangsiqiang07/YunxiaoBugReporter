import SwiftUI
import YunxiaoBugReporter

/// Bug 详情页：从 Bug 列表点击某一行进入，展示工作项的全部可用字段。
///
/// 字段基于 `YXBWorkitem`（容错解码），缺失的字段自动隐藏对应行，
/// 因此即便某些字段在列表接口中未返回，页面也不会出现空白占位。
struct BugDetailView: View {
    let item: YXBWorkitem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题区
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.subject.isEmpty ? "(无标题)" : item.subject)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !item.id.isEmpty {
                        Text("ID: \(item.id)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // 基本信息
                if hasBasicInfo {
                    detailSection("基本信息") {
                        rowIfPresent("状态", value: item.statusName)
                        rowIfPresent("负责人", value: item.assignedToName)
                        rowIfPresent("优先级", value: item.priorityName)
                        rowIfPresent("严重程度", value: item.severityName)
                        rowIfPresent("创建人", value: item.creatorName)
                        rowIfPresent("所属项目", value: item.spaceName)
                    }
                }

                // 描述（含图片渲染）
                if let description = item.description, !description.isEmpty {
                    let imageURLs = extractImageURLs(from: description)
                    let bodyText = textWithoutImages(description)
                    detailSection("描述") {
                        if !bodyText.isEmpty {
                            Text(bodyText)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !imageURLs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(imageURLs, id: \.absoluteString) { url in
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            HStack {
                                                Spacer()
                                                ProgressView()
                                                Spacer()
                                            }
                                            .frame(minHeight: 120)
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFit()
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        case .failure:
                                            HStack {
                                                Spacer()
                                                Image(systemName: "photo.fill")
                                                    .font(.largeTitle)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                            }
                                            .frame(minHeight: 120)
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 时间信息
                if item.gmtCreate != nil || item.gmtModified != nil {
                    detailSection("时间信息") {
                        rowIfPresent("创建时间", value: item.gmtCreate.map(formattedDate))
                        rowIfPresent("更新时间", value: item.gmtModified.map(formattedDate))
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Bug 详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 布局辅助

    private var hasBasicInfo: Bool {
        item.statusName != nil
            || item.assignedToName != nil
            || item.priorityName != nil
            || item.severityName != nil
            || item.creatorName != nil
            || item.spaceName != nil
    }

    @ViewBuilder
    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func rowIfPresent(_ label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func formattedDate(_ milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    // MARK: - 描述中的图片解析

    /// 从描述文本中提取图片地址（支持 HTML `<img src="...">` 与 Markdown `![](url)`）。
    private func extractImageURLs(from text: String) -> [URL] {
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

    /// 去掉描述中的图片标签与 Markdown 图片语法，并清除其余 HTML 标签，
    /// 得到用于纯文本展示的正文（图片已由 `extractImageURLs` 单独提取渲染）。
    private func textWithoutImages(_ text: String) -> String {
        var result = text
        // 1. 移除 HTML 图片标签
        if let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // 2. 移除 Markdown 图片语法 ![alt](url)
        if let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^)]+\)"#, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // 3. 移除其余 HTML 标签（如 <p>、<br>、<div> 等），避免把标签当作正文显示
        if let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // 4. 压缩多余空行
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

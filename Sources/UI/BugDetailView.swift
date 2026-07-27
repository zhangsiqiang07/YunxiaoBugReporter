import SwiftUI

/// Bug 详情页：从 Bug 列表点击某一行进入。
///
/// 进入页面后会调用云效「获取工作项详情」接口拉取完整数据（含描述、编号等），
/// 列表行携带的字段仅作为首屏占位，最终以接口返回为准。
///
/// 字段基于 `YXBWorkitem`（容错解码），缺失的字段自动隐藏对应行，
/// 因此即便某些字段在接口中未返回，页面也不会出现空白占位。
struct BugDetailView: View {
    let item: YXBWorkitem
    @EnvironmentObject private var store: YXBConfigStore

    /// 详情接口返回的数据；为 nil 时回退到列表行携带的 `item`（首屏占位）。
    @State private var detail: YXBWorkitem?
    @State private var isLoadingDetail = false
    @State private var detailError: String?
    @State private var hasLoadedDetail = false

    /// 实际展示的数据：优先用接口详情，否则用列表行数据。
    private var displayed: YXBWorkitem { detail ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 详情加载状态
                if isLoadingDetail {
                    HStack {
                        Spacer()
                        ProgressView("加载详情…")
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                if let detailError = detailError {
                    Text(detailError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // 标题区
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayed.subject.isEmpty ? "(无标题)" : displayed.subject)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !displayed.id.isEmpty {
                        Text("ID: \(displayed.id)")
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
                        rowIfPresent("编号", value: displayed.serialNumber)
                        rowIfPresent("状态", value: displayed.statusName)
                        rowIfPresent("负责人", value: displayed.assignedToName)
                        rowIfPresent("优先级", value: displayed.priorityName)
                        rowIfPresent("严重程度", value: displayed.severityName)
                        rowIfPresent("创建人", value: displayed.creatorName)
                        rowIfPresent("所属项目", value: displayed.spaceName)
                    }
                }

                // 描述（含图片渲染）
                if let description = displayed.description, !description.isEmpty {
                    let parsed = YXBDescriptionParser.parse(description)
                    detailSection("描述") {
                        if !parsed.text.isEmpty {
                            Text(parsed.text)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !parsed.imageURLs.isEmpty, let reporter = try? makeReporter() {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(parsed.imageURLs, id: \.absoluteString) { url in
                                    AuthImageView(url: url, workitemID: displayed.id, reporter: reporter)
                                }
                            }
                        }
                    }
                }

                // 时间信息
                if displayed.gmtCreate != nil || displayed.gmtModified != nil {
                    detailSection("时间信息") {
                        rowIfPresent("创建时间", value: displayed.gmtCreate.map(formattedDate))
                        rowIfPresent("更新时间", value: displayed.gmtModified.map(formattedDate))
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Bug 详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
        }
    }

    // MARK: - 数据加载

    /// 进入详情页时拉取工作项完整数据。接口失败不影响首屏（仍显示列表行数据）。
    private func loadDetail() async {
        guard !hasLoadedDetail else { return }
        guard !item.id.isEmpty else { return }
        hasLoadedDetail = true
        await MainActor.run {
            isLoadingDetail = true
            detailError = nil
        }
        do {
            let reporter = try makeReporter()
            let fetched = try await reporter.getWorkitem(workitemID: item.id)
            await MainActor.run {
                detail = fetched
                isLoadingDetail = false
            }
        } catch {
            await MainActor.run {
                detailError = "加载详情失败：\(error.localizedDescription)"
                isLoadingDetail = false
            }
        }
    }

    private func makeReporter() throws -> YunxiaoBugReporter {
        let reporter = YunxiaoBugReporter()
        // 详情接口（GET /workitems/{id}）不依赖 projectID，用占位配置避免校验拦截。
        try reporter.configure(store.buildConfigurationForProjectListing())
        return reporter
    }

    // MARK: - 布局辅助

    private var hasBasicInfo: Bool {
        displayed.serialNumber != nil
            || displayed.statusName != nil
            || displayed.assignedToName != nil
            || displayed.priorityName != nil
            || displayed.severityName != nil
            || displayed.creatorName != nil
            || displayed.spaceName != nil
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

}

import SwiftUI

/// 当前项目的 Bug 列表页（Tab 第一屏）。
///
/// - 左上角：切换项目（从组织项目列表中选，默认选中最新建立的项目）；
/// - 右上角：「提交 Bug」按钮，进入 `SubmitView`；
/// - 列表：分页加载（滚动到底部自动加载下一页），支持下拉刷新；
///   点击某一行可查看工作项详情（演示中仅展示基本信息）。
public struct BugListView: View {
    @EnvironmentObject private var store: YXBConfigStore

    public init() {}

    @State private var workitems: [YXBWorkitem] = []
    @State private var page = 1
    private let perPage = 20

    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var isRefreshing = false
    @State private var hasMore = true
    @State private var errorMessage: String?

    @State private var navigateToSubmit = false
    @State private var showProjectPicker = false
    @State private var projectOptions: [YXBProject] = []
    @State private var isLoadingProjects = false

    public var body: some View {
        List {
            if let errorMessage, workitems.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            ForEach(workitems) { item in
                NavigationLink(destination: BugDetailView(item: item)) {
                    WorkitemRow(item: item)
                }
                .onAppear { loadMoreIfNeeded(current: item) }
            }

            if isLoadingMore {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("加载更多…")
                        Spacer()
                    }
                }
            } else if hasMore == false, !workitems.isEmpty {
                Section {
                    Text("没有更多了")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if workitems.isEmpty, !isLoading {
                Section {
                    Text(emptyHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bug 列表")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    Task { await ensureProjectsLoaded() }
                    showProjectPicker = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                        Text(currentProjectName)
                            .lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    navigateToSubmit = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("提交 Bug")
            }
        }
        .sheet(isPresented: $showProjectPicker) {
            projectPickerSheet
        }
        // iOS 15 兼容：用隐藏的 NavigationLink(isActive:) 实现编程式 push，
        // 替代 iOS 16 才有的 .navigationDestination(isPresented:)。
        .background(
            NavigationLink(destination: SubmitView(), isActive: $navigateToSubmit) {
                EmptyView()
            }
            .hidden()
        )
        .refreshable {
            await reload()
        }
        .task {
            await ensureProjectsLoaded()
            await reload()
        }
    }

    // MARK: - 数据加载

    /// 首次进入时确保项目列表已加载；若尚未选择项目，默认选中组织内最新建立的项目。
    private func ensureProjectsLoaded() async {
        guard projectOptions.isEmpty else { return }
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        do {
            let reporter = try makeReporterForProjects()
            let projects = try await reporter.listOrganizationProjects()
            await MainActor.run {
                projectOptions = projects
                if store.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let newest = projects.first {
                    store.projectID = newest.id
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "加载项目失败：\(error.localizedDescription)"
            }
        }
    }

    /// 重新拉取第一页（下拉刷新 / 切换项目后调用）。
    private func reload() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        isLoading = true
        errorMessage = nil
        defer {
            isRefreshing = false
            isLoading = false
        }
        await loadPage(initial: true)
    }

    /// 滚动到底部时按需加载下一页。
    private func loadMoreIfNeeded(current item: YXBWorkitem) {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard item.id == workitems.last?.id else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await loadPage(initial: false)
    }

    private func loadPage(initial: Bool) async {
        let targetPage = initial ? 1 : page + 1
        do {
            let reporter = try makeReporter()
            let items = try await reporter.listWorkitems(page: targetPage, perPage: perPage)
            await MainActor.run {
                if initial {
                    workitems = items
                    page = 1
                } else {
                    workitems.append(contentsOf: items)
                    page = targetPage
                }
                // 返回的条数小于每页大小，说明已是最后一页。
                hasMore = items.count >= perPage
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                if initial {
                    workitems = []
                }
                errorMessage = "加载 Bug 列表失败：\(error.localizedDescription)"
                hasMore = false
            }
        }
    }

    // MARK: - 辅助

    private var currentProjectName: String {
        let pid = store.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        if pid.isEmpty { return "选择项目" }
        if let project = projectOptions.first(where: { $0.id == pid }) {
            return project.name.isEmpty ? project.id : project.name
        }
        return pid
    }

    private var emptyHint: String {
        if store.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先选择项目（点击左上角）"
        }
        return "暂无 Bug"
    }

    private func makeReporter() throws -> YunxiaoBugReporter {
        let reporter = YunxiaoBugReporter()
        try reporter.configure(store.buildConfiguration())
        return reporter
    }

    private func makeReporterForProjects() throws -> YunxiaoBugReporter {
        let reporter = YunxiaoBugReporter()
        try reporter.configure(store.buildConfigurationForProjectListing())
        return reporter
    }

    // MARK: - 项目切换 Sheet

    private var projectPickerSheet: some View {
        NavigationView {
            List {
                if isLoadingProjects {
                    Section { HStack { Spacer(); ProgressView(); Spacer() } }
                }
                ForEach(projectOptions) { project in
                    Button {
                        store.projectID = project.id
                        showProjectPicker = false
                        Task { await reload() }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name.isEmpty ? project.id : project.name)
                                    .foregroundStyle(.primary)
                                if !project.id.isEmpty {
                                    Text(project.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if project.id == store.projectID.trimmingCharacters(in: .whitespacesAndNewlines) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("切换项目")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showProjectPicker = false }
                }
            }
            .refreshable {
                isLoadingProjects = true
                defer { isLoadingProjects = false }
                do {
                    let reporter = try makeReporterForProjects()
                    let projects = try await reporter.listOrganizationProjects()
                    await MainActor.run { projectOptions = projects }
                } catch {
                    await MainActor.run { errorMessage = "刷新项目失败：\(error.localizedDescription)" }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

/// 单个工作项行：标题 + 状态 + 负责人 + 创建时间。
struct WorkitemRow: View {
    let item: YXBWorkitem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.subject.isEmpty ? "(无标题)" : item.subject)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 12) {
                if let status = item.statusName, !status.isEmpty {
                    Label(status, systemImage: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let assignee = item.assignedToName, !assignee.isEmpty {
                    Label(assignee, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let created = item.gmtCreate {
                    Text(formattedDate(created))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

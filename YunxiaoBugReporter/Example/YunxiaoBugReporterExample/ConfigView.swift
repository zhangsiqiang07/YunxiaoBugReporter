import SwiftUI
import YunxiaoBugReporter

/// 云效配置页面。两种模式：
/// - `.forced`：未配置时强制展示，隐藏返回按钮，保存后回调 `onComplete` 进入主界面；
/// - `.normal`：作为 Tab 之一，可随时修改保存。
///
/// 列表型参数（负责人、工作项类型）通过云效 API 拉取选项，以「选择」方式录入，
/// 拉取失败时回退为手动输入，避免硬编码 ID。
struct ConfigView: View {
    enum Mode { case normal, forced }

    let mode: Mode
    var onComplete: (() -> Void)? = nil

    @EnvironmentObject private var store: DemoConfigStore
    @State private var showErrors = false
    @State private var errorMessages: [String] = []

    @State private var memberOptions: [YXBMember] = []
    @State private var typeOptions: [YXBWorkitemType] = []
    @State private var projectOptions: [YXBProject] = []
    @State private var isLoadingMembers = false
    @State private var isLoadingTypes = false
    @State private var isLoadingProjects = false
    @State private var loadMessage: String?

    var body: some View {
        Form {
            Section {
                // 域名、组织 ID 写死在 DemoConstants，自动只读展示，无需手动填写。
                infoRow("服务域名", value: DemoConstants.domain)
                Picker("版本", selection: $store.editionRaw) {
                    Text("中心版").tag("standard")
                    Text("Region 版").tag("region")
                }
                .pickerStyle(.segmented)
                if store.editionRaw == "standard" {
                    infoRow("组织 ID", value: DemoConstants.organizationID)
                }
                // 项目：优先以组织项目列表选择（默认选中最新建立的项目）；列表为空时回退手动输入。
                if projectOptions.isEmpty {
                    TextField("项目 ID", text: $store.projectID)
                        .textInputAutocapitalization(.never)
                } else {
                    Picker("项目", selection: $store.projectID) {
                        ForEach(projectOptions) { project in
                            Text(project.name.isEmpty ? project.id : project.name).tag(project.id)
                        }
                    }
                    if let current = projectOptions.first(where: { $0.id == store.projectID }) {
                        Text("当前选择：\(current.name.isEmpty ? current.id : current.name)（\(current.id)）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // 负责人：优先以成员列表选择；列表为空时回退手动输入。
                if memberOptions.isEmpty {
                    TextField("负责人用户 ID", text: $store.assignedTo)
                        .textInputAutocapitalization(.never)
                        .onChange(of: store.assignedTo) { _ in
                            // 手动输入时无法获知姓名，清空展示名。
                            store.assignedToName = ""
                        }
                } else {
                    Picker("负责人", selection: $store.assignedTo) {
                        ForEach(memberOptions) { member in
                            Text(member.name).tag(member.id)
                        }
                    }
                    .onChange(of: store.assignedTo) { newValue in
                        store.assignedToName = memberOptions.first(where: { $0.id == newValue })?.name ?? ""
                    }
                    if !store.assignedToName.isEmpty {
                        Text("当前选择：\(store.assignedToName)（\(store.assignedTo)）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await loadMembers() }
                } label: {
                    if isLoadingMembers {
                        ProgressView()
                    } else {
                        Text(memberOptions.isEmpty ? "从成员列表加载负责人" : "重新加载成员列表")
                    }
                }
                .disabled(isLoadingMembers)

                // 工作项类型：以类型列表选择，默认「自动选择」。
                Picker("工作项类型", selection: $store.workitemTypeID) {
                    Text("自动选择（默认）").tag("")
                    ForEach(typeOptions) { type in
                        Text(type.name ?? type.id).tag(type.id)
                    }
                }
                Button {
                    Task { await loadTypes() }
                } label: {
                    if isLoadingTypes {
                        ProgressView()
                    } else {
                        Text(typeOptions.isEmpty ? "从类型列表加载" : "重新加载类型列表")
                    }
                }
                .disabled(isLoadingTypes)

                // 项目：从组织项目列表加载，默认选中最新建立的项目。
                Button {
                    Task { await loadProjects() }
                } label: {
                    if isLoadingProjects {
                        ProgressView()
                    } else {
                        Text(projectOptions.isEmpty ? "从组织项目列表加载" : "重新加载项目列表")
                    }
                }
                .disabled(isLoadingProjects)
            } header: { Text("云效服务") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("「工作项类型」留空时由 SDK 自动选择 Bug 类型；「项目」点击「从组织项目列表加载」后从组织内项目选择，默认选中最新建立的项目；负责人为必填；域名 / 组织 ID / Token 已写死在代码中并自动展示。")
                    if let loadMessage {
                        Text(loadMessage)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                // Token 写死在 DemoConstants，自动只读展示；需要变更时直接改代码常量。
                infoRow("云效访问 Token", value: DemoConstants.token, lines: 3)
                Text("Token 写死在 DemoConstants（明文仅用于演示，生产环境请勿如此）；拉取成员/类型列表需要该 Token 具备对应只读权限。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: { Text("访问凭证") }

            Section("结果缓存（可选）") {
                Toggle("启用缓存", isOn: $store.cacheEnabled)
                if store.cacheEnabled {
                    Picker("缓存后端", selection: $store.cacheBackendRaw) {
                        Text("内存（推荐）").tag("memory")
                        Text("UserDefaults").tag("userDefaults")
                    }
                    Stepper("工作项类型 TTL：\(Int(store.workitemTypeCacheTTL)) 秒",
                            value: $store.workitemTypeCacheTTL, in: 60...86400, step: 60)
                    Stepper("Token TTL：\(Int(store.tokenCacheTTL)) 秒",
                            value: $store.tokenCacheTTL, in: 0...86400, step: 60)
                }
            }
        }
        .navigationTitle(mode == .forced ? "配置云效" : "云效配置")
        .navigationBarBackButtonHidden(mode == .forced)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { save() }
            }
        }
        .alert("配置不完整", isPresented: $showErrors) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessages.joined(separator: "\n"))
        }
        .onAppear {
            // 项目列表接口仅依赖 organizationID，与 projectID 无关，故即使在尚未选择项目时
            // 也静默预拉取，便于默认可用并自动选中最新建立的项目。
            Task { await loadProjects(silent: true) }
            // 已具备最小配置时，静默预拉取成员/类型列表，使选择器默认可用。
            guard store.isConfigured else { return }
            Task { await loadMembers(silent: true) }
            Task { await loadTypes(silent: true) }
        }
    }

    // MARK: - 列表拉取

    private func makeReporter() -> YunxiaoBugReporter? {
        do {
            let reporter = YunxiaoBugReporter()
            try reporter.configure(store.buildConfiguration())
            return reporter
        } catch {
            return nil
        }
    }

    /// 只读信息行：左侧标题，右侧值（右对齐、可折行）。用于展示写死在代码中的配置。
    private func infoRow(_ title: String, value: String, lines: Int = 1) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(lines)
                .minimumScaleFactor(0.5)
        }
    }

    private func loadMembers(silent: Bool = false) async {
        isLoadingMembers = true
        defer { isLoadingMembers = false }
        guard let reporter = makeReporter() else {
            if !silent { await MainActor.run { loadMessage = "请先填写域名、项目、Token 等必填项后再加载成员。" } }
            return
        }
        do {
            let members = try await reporter.listProjectMembers()
            await MainActor.run {
                memberOptions = members
                if !silent {
                    loadMessage = members.isEmpty ? "未获取到成员，可手动填写负责人 ID。" : "已加载 \(members.count) 名成员。"
                }
            }
        } catch {
            await MainActor.run {
                if !silent { loadMessage = "加载成员失败：\(error.localizedDescription)" }
            }
        }
    }

    private func loadTypes(silent: Bool = false) async {
        isLoadingTypes = true
        defer { isLoadingTypes = false }
        guard let reporter = makeReporter() else {
            if !silent { await MainActor.run { loadMessage = "请先填写域名、项目、Token 等必填项后再加载类型。" } }
            return
        }
        do {
            let types = try await reporter.listBugTypes()
            await MainActor.run {
                typeOptions = types
                if !silent {
                    loadMessage = types.isEmpty ? "未获取到工作项类型。" : "已加载 \(types.count) 个工作项类型。"
                }
            }
        } catch {
            await MainActor.run {
                if !silent { loadMessage = "加载类型失败：\(error.localizedDescription)" }
            }
        }
    }

    private func loadProjects(silent: Bool = false) async {
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        guard let reporter = makeReporterForProjects() else {
            if !silent { await MainActor.run { loadMessage = "请先填写域名、组织 ID、Token 等必填项后再加载项目。" } }
            return
        }
        do {
            let projects = try await reporter.listOrganizationProjects()
            await MainActor.run {
                projectOptions = projects
                // 尚未选择项目时，默认选中「组织内最新建立的项目」（列表已按 gmtCreate 倒序）。
                if store.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let newest = projects.first {
                    store.projectID = newest.id
                }
                if !silent {
                    if projects.isEmpty {
                        loadMessage = "未获取到项目，可手动填写项目 ID。"
                    } else {
                        let newestName = projects.first?.name.isEmpty == false
                            ? (projects.first?.name ?? "") : (projects.first?.id ?? "")
                        loadMessage = "已加载 \(projects.count) 个项目，默认选中最新建立的「\(newestName)」。"
                    }
                }
            }
        } catch {
            await MainActor.run {
                if !silent { loadMessage = "加载项目失败：\(error.localizedDescription)" }
            }
        }
    }

    private func makeReporterForProjects() -> YunxiaoBugReporter? {
        do {
            let reporter = YunxiaoBugReporter()
            // 项目列表接口不需要 projectID / assignedTo，这里用占位绕过 configure 校验。
            try reporter.configure(store.buildConfigurationForProjectListing())
            return reporter
        } catch {
            return nil
        }
    }

    private func save() {
        let issues = store.validationErrors()
        if !issues.isEmpty {
            errorMessages = issues
            showErrors = true
            return
        }
        store.save()
        onComplete?()
    }
}

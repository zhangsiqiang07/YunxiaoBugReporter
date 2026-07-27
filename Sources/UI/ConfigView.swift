import SwiftUI

/// 云效配置页面。两种模式：
/// - `.forced`：未配置时强制展示，隐藏返回按钮，保存后回调 `onComplete` 进入主界面；
/// - `.normal`：作为 Tab 之一，可随时修改保存。
///
/// 列表型参数（负责人、工作项类型）通过云效 API 拉取选项，以「选择」方式录入，
/// 拉取失败时回退为手动输入，避免硬编码 ID。
public struct ConfigView: View {
    public enum Mode { case normal, forced }

    let mode: Mode
    var onComplete: (() -> Void)? = nil
    /// 宿主注入的退出回调：点击导航栏「退出」时调用，由 Example 负责 dismiss 全屏根界面。
    /// 非可选，默认空实现（避免在 @ToolbarContentBuilder 内使用 `if` 触发 iOS 16 的 buildIf 限制）。
    var onExit: () -> Void = {}

    public init(mode: Mode, onComplete: (() -> Void)? = nil, onExit: (() -> Void)? = nil) {
        self.mode = mode
        self.onComplete = onComplete
        self.onExit = onExit ?? {}
    }

    @EnvironmentObject private var store: YXBConfigStore
    @State private var showErrors = false
    @State private var errorMessages: [String] = []

    @State private var memberOptions: [YXBMember] = []
    @State private var typeOptions: [YXBWorkitemType] = []
    @State private var projectOptions: [YXBProject] = []
    @State private var isLoadingMembers = false
    @State private var isLoadingTypes = false
    @State private var isLoadingProjects = false
    @State private var loadMessage: String?

    public var body: some View {
        Form {
            Section {
                // 域名、组织 ID 由宿主注入，自动只读展示，无需手动填写。
                infoRow("服务域名", value: store.domain)
                Picker("版本", selection: $store.editionRaw) {
                    Text("中心版").tag("standard")
                    Text("Region 版").tag("region")
                }
                .pickerStyle(.segmented)
                if store.editionRaw == "standard" {
                    infoRow("组织 ID", value: store.organizationID)
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
                    Text("「工作项类型」留空时由 SDK 自动选择 Bug 类型；「项目」点击「从组织项目列表加载」后从组织内项目选择，默认选中最新建立的项目；「负责人」为提交必填项，但配置页可留空、提交时再校验，且无需先手填 ID——选定项目后点「从成员列表加载负责人」即可从下拉选择（切换项目会自动重新拉取）；域名 / 组织 ID 由宿主初始化时注入并自动展示，访问 Token 可在下方「访问凭证」中修改（默认使用初始化注入的值）。")
                    if let loadMessage = loadMessage {
                        Text(loadMessage)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                // Token 默认可编辑：初始值为宿主初始化注入的默认 Token，可在此修改并保存；
                // 留空则回退到注入的默认值（见 YXBConfigStore.resolvedToken）。
                // iOS 15 兼容：不使用 axis:.vertical / lineLimit(reservesSpace:)（均为 iOS 16+）。
                // Token 为单行字符串，单行 TextField 更合适。
                TextField("云效访问 Token", text: $store.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("默认使用初始化注入的 Token，可在此临时修改并保存（明文仅用于演示，生产环境请勿如此）；留空则回退到默认值。拉取成员/类型/项目列表需要该 Token 具备对应只读权限。")
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onExit()
                } label: {
                    Text("退出").foregroundStyle(.red)
                }
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
            // 项目已确定后，静默预拉取成员 / 类型列表，使「负责人」等选择器默认可用。
            // 这些列表仅依赖 projectID，与负责人(assignedTo)无关，故无需先填负责人。
            autoLoadScopedLists()
        }
        .onChange(of: store.projectID) { _ in
            // 用户在「项目」选择器切换后，自动重新拉取该项目下的成员 / 类型列表。
            autoLoadScopedLists()
        }
    }

    // MARK: - 列表拉取

    /// 构造仅用于拉取「项目级列表」（成员 / 工作项类型）的 reporter。
    ///
    /// 成员与类型接口均为项目级，仅依赖 `projectID`，与 `assignedTo`（负责人）无关。
    /// `configure()` 要求 `assignedTo` 非空，但查询这些列表并不需要它；因此用
    /// `buildConfigurationForMemberListing()`（为空时以占位值绕过校验），
    /// 使「负责人」可在列表加载后再从下拉选择，无需先手填 ID。
    private func makeReporterForMemberListing() -> YunxiaoBugReporter? {
        do {
            let reporter = YunxiaoBugReporter()
            try reporter.configure(store.buildConfigurationForMemberListing())
            return reporter
        } catch {
            return nil
        }
    }

    /// 项目已配置时，静默预拉取成员与类型列表（仅依赖 projectID，无需负责人）。
    private func autoLoadScopedLists() {
        guard !store.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await loadMembers(silent: true) }
        Task { await loadTypes(silent: true) }
    }

    /// 只读信息行：左侧标题，右侧值（右对齐、可折行）。用于展示由宿主注入的配置。
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
        guard let reporter = makeReporterForMemberListing() else {
            if !silent { await MainActor.run { loadMessage = "请先填写域名、组织 ID、项目、Token 等必填项后再加载成员。" } }
            return
        }
        do {
            let members = try await reporter.listProjectMembers()
            await MainActor.run {
                memberOptions = members
                // 若当前已配置（含注入的默认负责人）的负责人命中成员列表，补上展示名。
                if let current = members.first(where: { $0.id == store.assignedTo }) {
                    store.assignedToName = current.name
                }
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
        guard let reporter = makeReporterForMemberListing() else {
            if !silent { await MainActor.run { loadMessage = "请先填写域名、组织 ID、项目、Token 等必填项后再加载类型。" } }
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

import SwiftUI
import PhotosUI

/// Bug 提交页面：选择快捷分类、描述现象（可语音）、附加标注截图，点击提交。
///
/// 交互遵循产品方案（AI 整理部分暂为 TODO）：
/// 1. 自动采集环境信息（设备 / App / 截图数等由 SDK 采集；页面 / 路由 / 网络 / 操作轨迹 / 最近网络请求由宿主通过 `YXBHostContext` 快照注入）；
/// 2. 用户选择快捷分类（问题类型 / 严重程度 / 发生频率）；
/// 3. 用户输入一句现象描述（点击键盘麦克风可语音输入），可用 AI 整理为同一可编辑草稿；
/// 4. 提交时组装为规范描述并附带分类标签，调用云效创建工作项 + 上传截图。
public struct SubmitView: View {
    @EnvironmentObject private var store: YXBConfigStore
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - sourceImages: 由「原应用」注入的截图（如宿主 App 截图后带入提 Bug 页面），
    ///     作为预置附件展示，用户可继续增删或框选 / 箭头标注。默认空。
    ///   - hostContext: 宿主在触发点（如 DoKit 长按）冻结的上下文快照（页面 / 路由 / 网络 /
    ///     操作轨迹 / 最近网络请求），由宿主侧采集器 `snapshot()` 产出。SDK 只消费、不采集。
    ///     传 `nil` 时回退到 `YXBConfigStore` 的实时注入值。默认 `nil`。
    ///   - onDismiss: 宿主提供的关闭回调。当 `SubmitView` 被包在 `UIHostingController`
    ///     经 UIKit `present` 弹出时，SwiftUI 的 `@Environment(\.dismiss)` 无法收起该页面，
    ///     需由宿主在回调里 `dismiss` 对应的 `UIViewController`。传 `nil` 时回退到 SwiftUI 自带
    ///     `dismiss`（适用于 `.sheet` / `.fullScreenCover` 等 SwiftUI 托管场景）。默认 `nil`。
    public init(
        sourceImages: [UIImage] = [],
        hostContext: YXBHostContext? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        _images = State(initialValue: sourceImages.map { IdentifiedImage(image: $0) })
        self.hostContext = hostContext
        self.onDismiss = onDismiss
    }

    /// 宿主冻结的上下文快照；优先于 `YXBConfigStore` 的实时值，
    /// 以避免进入上报页后 SDK 自身请求污染「最近网络」。
    let hostContext: YXBHostContext?

    /// 宿主提供的关闭回调（UIKit 弹出场景下收起 `UIHostingController` 用）；
    /// 为 `nil` 时回退到 SwiftUI 自带 `dismiss`。
    let onDismiss: (@MainActor () -> Void)?

    /// AI 生成的标题建议；完整标题会叠加当前分类标签（见 `composedTitle`）。
    @State private var generatedTitle = ""
    // MARK: - 单一 Bug 描述输入（AI 整理后复用为可编辑的规范草稿）
    @State private var userDescription = ""
    @State private var isFormattingWithAI = false
    @State private var aiFormattingMessage: String?
    @State private var aiFormattingFailed = false
    /// 描述格式：默认 Markdown，使组装的「## 标题」与环境信息列表渲染更清晰。
    @State private var formatRaw = "MD"

    // MARK: - 快捷分类（问题类型 / 严重程度 / 发生频率）
    @State private var issueType: YXBIssueType? = .function
    @State private var severity: YXBSeverity?
    @State private var frequency: YXBFrequency? = .always

    @State private var images: [IdentifiedImage] = []
    @State private var isSubmitting = false
    @State private var resultText: String?
    @State private var resultIsError = false
    @State private var showPicker = false
    /// 当前正在标注的图片（点开缩略图进入全屏标注器）。
    @State private var annotateTarget: AnnotateTarget?

    /// 自动采集的上下文（onAppear 采集一次；展示时叠加宿主注入值并按时截图数更新）。
    @State private var baseContext: YXBBugContext?
    @State private var showContext = false

    // MARK: - 工作项类型字段（必填列表项）
    @State private var fieldDefinitions: [YXBFieldDefinition] = []
    @State private var customFieldValues: [String: String] = [:]
    @State private var isLoadingFields = false
    @State private var fieldLoadError: String?

    // MARK: - 负责人（成员）字段
    @State private var memberOptions: [YXBMember] = []
    @State private var isLoadingMembers = false
    @State private var memberLoadError: String?

    public var body: some View {
        Form {
            Section("指派给") {
                if isLoadingMembers {
                    HStack {
                        Text("加载成员中…")
                        Spacer()
                        ProgressView()
                    }
                } else if memberOptions.isEmpty {
                    // 成员列表为空（未配置 / 拉取失败）时，回退为手动输入用户 ID。
                    TextField("负责人用户 ID", text: $store.assignedTo)
                        .textInputAutocapitalization(.never)
                        .onChange(of: store.assignedTo) { _ in
                            store.assignedToName = ""
                            store.save()
                        }
                    if let message = memberLoadError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Picker("负责人", selection: $store.assignedTo) {
                        ForEach(memberOptions) { member in
                            Text(member.name).tag(member.id)
                        }
                    }
                    .onChange(of: store.assignedTo) { newValue in
                        store.assignedToName = memberOptions.first(where: { $0.id == newValue })?.name ?? ""
                        store.save()
                    }
                    if !store.assignedToName.isEmpty {
                        Text("当前选择：\(store.assignedToName)（\(store.assignedTo)）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !memberOptions.isEmpty || memberLoadError != nil {
                    Button {
                        Task { await loadMembers() }
                    } label: {
                        if isLoadingMembers {
                            ProgressView()
                        } else {
                            Text("重新加载成员列表")
                        }
                    }
                    .disabled(isLoadingMembers)
                }
            }

            requiredFieldsSection

            Section("问题分类（可选，用于标题标签与描述）") {
                ChipGroup(title: "问题类型", options: YXBIssueType.allCases, display: { $0.displayName }, selection: $issueType)
                // 若云效工作项类型已把「严重程度」作为必填字段（上边会渲染为胶囊），
                // 则此处不再重复提供，避免两处选择。
                if severityField == nil {
                    ChipGroup(title: "严重程度", options: YXBSeverity.allCases, display: { $0.displayName }, selection: $severity)
                }
                ChipGroup(title: "发生频率", options: YXBFrequency.allCases, display: { $0.displayName }, selection: $frequency)
            }

            Section("Bug 描述") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(generatedTitle.isEmpty ? "用一句话描述现象（点击键盘麦克风可语音输入）" : "AI 整理内容（可直接修改）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $userDescription)
                        .frame(minHeight: generatedTitle.isEmpty ? 120 : 240)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                }

                if store.aiServiceDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("未配置 Bug AI 服务，仍可手动填写。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await formatWithAI() }
                    } label: {
                        if isFormattingWithAI {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("AI 整理中…")
                            }
                        } else {
                            Label("AI 整理并回填", systemImage: "sparkles")
                        }
                    }
                    .disabled(isFormattingWithAI || userDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("根据现象描述和已脱敏上下文，回填 Bug 标题、复现步骤和结果")

                    if let message = aiFormattingMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(aiFormattingFailed ? .red : .secondary)
                    }
                }

                if !generatedTitle.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("提交标题（自动生成）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(composedTitle)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Picker("描述格式", selection: $formatRaw) {
                    Text("Markdown").tag("MD")
                    Text("纯文本").tag("TEXT")
                }
                .pickerStyle(.segmented)
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(images) { item in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    annotateTarget = AnnotateTarget(id: item.id, image: item.image, annotations: item.annotations)
                                } label: {
                                    ZStack {
                                        Image(uiImage: item.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 76, height: 76)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        annotationOverlay(for: item.annotations, in: CGSize(width: 76, height: 76), imageSize: item.image.size)
                                    }
                                }
                                Button {
                                    images.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .font(.system(size: 20))
                                }
                                .padding(4)
                            }
                        }
                        Button {
                            showPicker = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.tint)
                                .frame(width: 76, height: 76)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: { Text("截图附件（可选，点开可标注红框 / 箭头）") }

            Section {
                let ctx = liveContext
                DisclosureGroup("自动采集环境信息", isExpanded: $showContext) {
                    ForEach(Array(ctx.descriptionLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.footnote)
                    }
                    if !ctx.recentRequests.isEmpty {
                        Divider()
                        Text("最近网络请求（\(ctx.recentRequests.count) 条，认证信息已脱敏）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(ctx.recentRequests.prefix(8)) { crumb in
                            Text(YXBDescriptionComposer.networkSummary(crumb, prefix: ""))
                                .font(.footnote)
                        }
                    }
                    Text("设备 / App 由 SDK 采集；页面 / 路由 / 网络 / 操作 / 最近请求由宿主通过 YXBHostContext 注入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("提交 Bug")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(isSubmitting || !requiredFieldsFilled)
            }

            if let resultText = resultText {
                Section {
                    Text(resultText)
                        .font(.subheadline)
                        .foregroundStyle(resultIsError ? .red : .green)
                } header: { Text("结果") }
            }
        }
        .navigationTitle("提交 Bug")
        .sheet(isPresented: $showPicker) {
            PhotoPicker(images: $images)
        }
        .fullScreenCover(item: $annotateTarget) { target in
            ImageAnnotatorView(image: target.image, initialAnnotations: target.annotations) { new in
                if let index = images.firstIndex(where: { $0.id == target.id }) {
                    images[index].annotations = new
                }
                annotateTarget = nil
            }
        }
        .onAppear {
            guard !isLoadingFields else { return }
            Task { await loadFields() }
            Task { await loadMembers() }
            if baseContext == nil {
                baseContext = YXBBugContextCollector.collect(screenshotCount: images.count)
            }
        }
    }

    /// 实时上下文：以采集到的设备/App 信息为基础，先叠加 `YXBConfigStore` 的实时值，
    /// 再叠加宿主冻结的 `hostContext` 快照（快照优先，避免上报页内 SDK 自身请求污染）。
    private var liveContext: YXBBugContext {
        var ctx = baseContext ?? YXBBugContextCollector.collect(screenshotCount: images.count)
        ctx.screenshotCount = images.count
        if let page = store.currentPage, !page.isEmpty { ctx.page = page }
        if let route = store.currentRoute, !route.isEmpty { ctx.route = route }
        if let network = store.currentNetwork, !network.isEmpty { ctx.network = network }
        if !store.recentActions.isEmpty { ctx.recentActions = store.recentActions }

        // 宿主冻结快照（推荐）：在长按时一次性采集，优先级高于上面的实时值。
        if let h = hostContext {
            if let page = h.page, !page.isEmpty { ctx.page = page }
            if let route = h.route, !route.isEmpty { ctx.route = route }
            if let network = h.network, !network.isEmpty { ctx.network = network }
            if !h.recentActions.isEmpty { ctx.recentActions = h.recentActions }
            if !h.recentRequests.isEmpty { ctx.recentRequests = h.recentRequests }
        }
        return ctx
    }

    /// 自动拼接的标题：`【iOS】` + 分类标签 + AI 标题（AI 未启用时回退首行描述）。
    private var composedTitle: String {
        var parts: [String] = ["【iOS】"]
        if let t = issueType { parts.append("【\(t.displayName)】") }
        if let s = severity { parts.append("【\(s.displayName)】") }
        if let f = frequency { parts.append("【\(f.displayName)】") }
        let title = generatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            parts.append(title)
        } else if let firstLine = userDescription
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) {
            parts.append(String(firstLine.prefix(80)))
        }
        return parts.joined()
    }

    /// 云效工作项类型中「严重程度 / 优先级」类必填字段（若有），其选择将渲染为胶囊样式，
    /// 与问题分类的标签选择一致；此时问题分类里不再重复提供「严重程度」胶囊。
    private var severityField: YXBFieldDefinition? {
        requiredListFields.first { field in
            let n = field.name.lowercased()
            return n.contains("severity") || n.contains("严重") || n.contains("优先级") || n.contains("priority")
        }
    }

    /// 单一描述输入框的内容原样提交，并追加环境信息。
    private func buildDescription(context ctx: YXBBugContext) -> String {
        YXBDescriptionComposer.compose(body: userDescription, context: ctx)
    }

    // MARK: - AI 整理

    @MainActor
    private func formatWithAI() async {
        let description = userDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }

        let serviceDomain = store.aiServiceDomain
        let context = liveContext
        isFormattingWithAI = true
        aiFormattingMessage = nil
        defer { isFormattingWithAI = false }

        do {
            let formatter = try YXBRemoteBugAIFormatter(serviceDomain: serviceDomain)
            let report = try await formatter.generate(
                YXBBugAIGenerateRequest(
                    description: description,
                    issueType: issueType?.rawValue,
                    severity: severity?.rawValue,
                    frequency: aiFrequencyValue(frequency),
                    page: .init(name: context.page, route: context.route),
                    recentActions: Array(context.recentActions.prefix(50)),
                    environment: .init(
                        appVersion: context.appVersion,
                        build: context.build,
                        device: context.deviceModel,
                        osVersion: context.osVersion,
                        network: context.network
                    )
                )
            )
            applyAIReport(report)
            aiFormattingMessage = report.missingInformation.isEmpty
                ? "AI 建议已回填，你仍可继续编辑后再提交。"
                : "AI 建议已回填；建议补充：\(report.missingInformation.joined(separator: "、"))"
            aiFormattingFailed = false
        } catch {
            // AI 是辅助能力：失败仅提示，绝不清空或阻断人工填写与云效提交。
            aiFormattingMessage = "AI 整理失败：\(error.localizedDescription)"
            aiFormattingFailed = true
        }
    }

    private func applyAIReport(_ report: YXBBugAIGeneratedReport) {
        generatedTitle = report.title
        userDescription = formattedAIContent(report)
        issueType = YXBIssueType(rawValue: report.issueType ?? "")
        if let suggestedSeverity = YXBSeverity(rawValue: report.severity) {
            severity = suggestedSeverity
            applyAISeverityToCustomField(suggestedSeverity)
        } else {
            severity = nil
            if let field = severityField {
                customFieldValues[field.id] = nil
            }
        }
        switch report.frequency {
        case "always": frequency = .always
        case "often", "occasionally": frequency = .sometimes
        case "once": frequency = .first
        default: frequency = nil
        }
    }

    private func formattedAIContent(_ report: YXBBugAIGeneratedReport) -> String {
        var sections = ["## 问题描述\n\(report.actualResult)"]
        if !report.reproductionSteps.isEmpty {
            let numberedSteps = report.reproductionSteps
                .enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            sections.append("## 复现步骤\n\(numberedSteps)")
        }
        if let expected = report.expectedResult, !expected.isEmpty {
            let inferred = report.expectedResultInferred ? "（AI 推断）" : ""
            sections.append("## 期望结果\(inferred)\n\(expected)")
        }
        return sections.joined(separator: "\n\n")
    }

    private func aiFrequencyValue(_ value: YXBFrequency?) -> String? {
        switch value {
        case .always: return "always"
        case .sometimes: return "occasionally"
        case .first: return "once"
        case nil: return nil
        }
    }

    private func applyAISeverityToCustomField(_ suggestedSeverity: YXBSeverity) {
        guard let field = severityField,
              let option = field.options.first(where: {
                  $0.value.lowercased() == suggestedSeverity.rawValue
                      || $0.displayValue == suggestedSeverity.displayName
              }) else { return }
        customFieldValues[field.id] = option.id
    }

    /// 由快捷分类生成上报标签。
    private func buildLabels() -> [String] {
        var labels: [String] = []
        if let t = issueType { labels.append(t.label) }
        if let s = severity { labels.append(s.label) }
        if let f = frequency { labels.append(f.label) }
        return labels
    }

    // MARK: - 必填列表字段

    private var requiredListFields: [YXBFieldDefinition] {
        fieldDefinitions.filter {
            $0.required && (["list", "multiList"].contains($0.format)) && !$0.options.isEmpty
        }
    }

    private var requiredFieldsFilled: Bool {
        requiredListFields.allSatisfy {
            guard let value = customFieldValues[$0.id] else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @ViewBuilder
    private var requiredFieldsSection: some View {
        if isLoadingFields {
            Section("必填字段") {
                HStack {
                    Text("加载字段配置中…")
                    Spacer()
                    ProgressView()
                }
            }
        } else if let error = fieldLoadError {
            Section("必填字段") {
                Text("加载失败：\(error)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("重试") {
                    Task { await loadFields() }
                }
            }
        } else {
            ForEach(requiredListFields) { field in
                Section(field.name) {
                    ChipGroup(
                        title: nil,
                        options: field.options,
                        display: { $0.displayValue },
                        selection: chipBinding(for: field)
                    )
                }
            }
        }
    }

    /// 必填列表字段的胶囊选择绑定：选项直接映射到 `customFieldValues[field.id]`；
    /// 若为严重程度字段，best-effort 同步到 `severity` 枚举用于标题标签。
    private func chipBinding(for field: YXBFieldDefinition) -> Binding<YXBFieldOption?> {
        Binding<YXBFieldOption?>(
            get: {
                guard let id = customFieldValues[field.id], !id.isEmpty else { return nil }
                return field.options.first { $0.id == id }
            },
            set: { option in
                customFieldValues[field.id] = option?.id
                if field.id == severityField?.id, let opt = option {
                    severity = YXBSeverity.allCases.first {
                        $0.displayName == opt.displayValue
                            || $0.rawValue == opt.value.lowercased()
                    }
                }
            }
        )
    }

    // MARK: - 成员列表（负责人）加载

    private func makeReporterForMembers() -> YunxiaoBugReporter? {
        do {
            let reporter = YunxiaoBugReporter()
            try reporter.configure(store.buildConfigurationForMemberListing())
            return reporter
        } catch {
            return nil
        }
    }

    private func loadMembers() async {
        isLoadingMembers = true
        memberLoadError = nil
        defer { isLoadingMembers = false }
        guard let reporter = makeReporterForMembers() else {
            await MainActor.run {
                memberLoadError = "请先在「云效配置」中填写项目与 Token 后再加载成员。"
            }
            return
        }
        do {
            let members = try await reporter.listProjectMembers()
            await MainActor.run {
                memberOptions = members
                if let current = members.first(where: { $0.id == store.assignedTo }) {
                    store.assignedToName = current.name
                }
                memberLoadError = members.isEmpty ? "未获取到成员，可手动填写负责人 ID。" : nil
            }
        } catch {
            await MainActor.run {
                memberLoadError = "加载成员失败：\(error.localizedDescription)"
            }
        }
    }

    private func loadFields() async {
        isLoadingFields = true
        fieldLoadError = nil
        defer { isLoadingFields = false }

        do {
            let config = try store.buildConfiguration()
            let reporter = YunxiaoBugReporter()
            try reporter.configure(config)

            let typeID = try await resolveWorkitemTypeID(reporter: reporter)
            let fields = try await reporter.listWorkitemTypeFields(workitemTypeID: typeID)

            await MainActor.run {
                fieldDefinitions = fields
                applyDefaultFieldValues(fields: fields)
            }
        } catch {
            await MainActor.run {
                fieldLoadError = error.localizedDescription
            }
        }
    }

    private func resolveWorkitemTypeID(reporter: YunxiaoBugReporter) async throws -> String {
        let explicit = store.workitemTypeID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        let types = try await reporter.listBugTypes()
        guard let selected = types.first(where: { $0.category?.lowercased() == "bug" }) ?? types.first else {
            throw YXBError.workitemTypeNotFound
        }
        return selected.id
    }

    private func applyDefaultFieldValues(fields: [YXBFieldDefinition]) {
        for field in requiredListFields {
            guard customFieldValues[field.id] == nil,
                  let defaultValue = field.defaultValue,
                  !defaultValue.isEmpty else { continue }

            if field.options.contains(where: { $0.id == defaultValue }) {
                customFieldValues[field.id] = defaultValue
            } else if let matched = field.options.first(where: { $0.value == defaultValue }) {
                customFieldValues[field.id] = matched.id
            }
        }
    }

    // MARK: - 提交

    @MainActor
    private func submit() async {
        isSubmitting = true
        resultText = nil
        defer { isSubmitting = false }

        guard requiredFieldsFilled else {
            let missing = requiredListFields
                .filter { customFieldValues[$0.id]?.isEmpty ?? true }
                .map(\.name)
                .joined(separator: "、")
            resultText = "请填写必填字段：\(missing)"
            resultIsError = true
            return
        }

        guard !store.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resultText = "请选择负责人（指派给）后再提交。"
            resultIsError = true
            return
        }

        let ctx = liveContext

        // TODO: AI 结构化整理（接入 YXBBugAIFormatting 后在此调用）：
        //   将 userDescription + ctx 送入 AI，生成标题建议 / 复现步骤 / 严重程度建议等；
        //   AI 调用失败时必须回退到下方用户填写内容，不阻断提交。
        let descriptionText = buildDescription(context: ctx)
        let labels = buildLabels()

        do {
            let config = try store.buildConfiguration()
            let reporter = YunxiaoBugReporter()
            try reporter.configure(config)

            var attachments: [YXBAttachment] = []
            for (index, item) in images.enumerated() {
                // 若用户对截图做了标注（红框 / 红箭头），将其烘焙进图片后再上传。
                let baked = yxb_bakeAnnotations(into: item.image, annotations: item.annotations)
                if let data = baked.jpegData(compressionQuality: 0.8) {
                    attachments.append(
                        YXBAttachment(data: data, fileName: "screenshot-\(index + 1).jpg", mimeType: "image/jpeg")
                    )
                }
            }

            let report = YXBBugReport(
                title: composedTitle,
                description: descriptionText,
                format: formatRaw == "MD" ? .markdown : .plainText,
                customFields: customFieldValues,
                labels: labels,
                attachments: attachments
            )

            let result = try await reporter.submit(report)
            let status = result.status == .success ? "提交成功" : "部分成功（部分附件失败）"
            resultText = """
            \(status)
            workitemID: \(result.workitemID)
            成功附件: \(result.successfulAttachments.count)
            失败附件: \(result.failedAttachments.count)
            """
            resultIsError = false

            // 提交成功后自动关闭提交页（先停留 1 秒让用户看到结果）。
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let onDismiss {
                onDismiss()
            } else {
                dismiss()
            }
        } catch {
            resultText = "提交失败：\(error.localizedDescription)"
            resultIsError = true
        }
    }
}

/// 横向滚动的胶囊选择器，用于快捷分类 / 必填字段。
private struct ChipGroup<T: Identifiable & Hashable>: View {
    let title: String?
    let options: [T]
    let display: (T) -> String
    @Binding var selection: T?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        let isSelected = selection?.id == option.id
                        Button {
                            // 再次点击已选项可取消选择。
                            selection = isSelected ? nil : option
                        } label: {
                            Text(display(option))
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
}

/// 带稳定标识的选中图片，用于 `ForEach` 与删除。
struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
    /// 标注列表（红框 / 红箭头，归一化 0..1，相对图片内容绘制区）；空表示未标注。
    var annotations: [ImageAnnotation] = []

    init(image: UIImage, annotations: [ImageAnnotation] = []) {
        self.image = image
        self.annotations = annotations
    }
}

/// 当前正在全屏标注的目标图片。
struct AnnotateTarget: Identifiable {
    let id: UUID
    let image: UIImage
    let annotations: [ImageAnnotation]
}

/// 缩略图（scaledToFill 方形）上的红框 / 红箭头覆盖层。
private func annotationOverlay(for annotations: [ImageAnnotation], in frame: CGSize, imageSize: CGSize) -> some View {
    let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
    let drawnW = imageSize.width * scale
    let drawnH = imageSize.height * scale
    let offsetX = (frame.width - drawnW) / 2
    let offsetY = (frame.height - drawnH) / 2
    return ForEach(annotations) { ann in
        let s = CGPoint(x: offsetX + ann.start.x * drawnW, y: offsetY + ann.start.y * drawnH)
        let e = CGPoint(x: offsetX + ann.end.x * drawnW, y: offsetY + ann.end.y * drawnH)
        if ann.kind == .rect {
            let r = CGRect(
                x: min(s.x, e.x),
                y: min(s.y, e.y),
                width: abs(e.x - s.x),
                height: abs(e.y - s.y)
            )
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.red, lineWidth: 2)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
        } else {
            yxb_arrowPath(from: s, to: e)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

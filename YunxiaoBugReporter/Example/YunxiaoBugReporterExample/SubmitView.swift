import SwiftUI
import YunxiaoBugReporter
import PhotosUI

/// Bug 提交页面：填写标题/描述、选择描述格式、附加截图（可选），点击提交。
struct SubmitView: View {
    @EnvironmentObject private var store: DemoConfigStore

    @State private var title = ""
    @State private var description = ""
    @State private var formatRaw = "TEXT"
    @State private var images: [IdentifiedImage] = []
    @State private var isSubmitting = false
    @State private var resultText: String?
    @State private var resultIsError = false
    @State private var showPicker = false

    // MARK: - 工作项类型字段（必填列表项）
    @State private var fieldDefinitions: [YXBFieldDefinition] = []
    @State private var customFieldValues: [String: String] = [:]
    @State private var isLoadingFields = false
    @State private var fieldLoadError: String?

    // MARK: - 负责人（成员）字段
    @State private var memberOptions: [YXBMember] = []
    @State private var isLoadingMembers = false
    @State private var memberLoadError: String?

    var body: some View {
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
                            // 手动输入无法获知姓名，清空展示名并持久化。
                            store.assignedToName = ""
                            store.save()
                        }
                    if let message = memberLoadError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } else {
                    // 成员列表可用时，以「姓名」展示并可修改负责人（选中后以 ID 提交）。
                    Picker("负责人", selection: $store.assignedTo) {
                        ForEach(memberOptions) { member in
                            Text(member.name).tag(member.id)
                        }
                    }
                    .onChange(of: store.assignedTo) { newValue in
                        store.assignedToName = memberOptions.first(where: { $0.id == newValue })?.name ?? ""
                        // 修改负责人后立即持久化，使配置页与下次启动保持一致。
                        store.save()
                    }
                    if !store.assignedToName.isEmpty {
                        Text("当前选择：\(store.assignedToName)（\(store.assignedTo)）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // 成员列表已加载或上次加载失败时，提供「重新加载」入口。
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

            Section("Bug 信息") {
                TextField("标题", text: $title)
                Picker("描述格式", selection: $formatRaw) {
                    Text("纯文本").tag("TEXT")
                    Text("Markdown").tag("MD")
                }
                .pickerStyle(.segmented)
                TextEditor(text: $description)
                    .frame(minHeight: 120)
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(images) { item in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: item.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
            } header: { Text("截图附件（可选）") }

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
                .disabled(isSubmitting || title.trimmingCharacters(in: .whitespaces).isEmpty || !requiredFieldsFilled)
            }

            if let resultText {
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
        .onAppear {
            guard !isLoadingFields else { return }
            Task { await loadFields() }
            Task { await loadMembers() }
        }
    }

    /// 必填且为列表（单选/多选）的字段。
    private var requiredListFields: [YXBFieldDefinition] {
        fieldDefinitions.filter {
            $0.required && (["list", "multiList"].contains($0.format)) && !$0.options.isEmpty
        }
    }

    /// 所有必填列表字段是否都已选择。
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
                    Picker("", selection: binding(for: field.id)) {
                        Text("请选择").tag("")
                        ForEach(field.options) { option in
                            Text(option.displayValue).tag(option.id)
                        }
                    }
                }
            }
        }
    }

    private func binding(for fieldID: String) -> Binding<String> {
        Binding(
            get: { customFieldValues[fieldID] ?? "" },
            set: { customFieldValues[fieldID] = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - 成员列表（负责人）加载

    /// 用「成员列表专用」配置构造 reporter：即使尚未选择负责人（assignedTo 为空）也能拉取成员。
    private func makeReporterForMembers() -> YunxiaoBugReporter? {
        do {
            let reporter = YunxiaoBugReporter()
            try reporter.configure(store.buildConfigurationForMemberListing())
            return reporter
        } catch {
            return nil
        }
    }

    /// 拉取当前项目的成员列表，用于「负责人」选择器按姓名展示与选择。
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
                memberLoadError = members.isEmpty ? "未获取到成员，可手动填写负责人 ID。" : nil
            }
        } catch {
            await MainActor.run {
                memberLoadError = "加载成员失败：\(error.localizedDescription)"
            }
        }
    }

    /// 拉取当前工作项类型的字段定义，并自动为必填列表字段填入默认值。
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

            // 默认值通常是选项 id；若未命中，再尝试匹配 option.value（如 "3"）。
            if field.options.contains(where: { $0.id == defaultValue }) {
                customFieldValues[field.id] = defaultValue
            } else if let matched = field.options.first(where: { $0.value == defaultValue }) {
                customFieldValues[field.id] = matched.id
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        resultText = nil
        defer { isSubmitting = false }

        // 前置校验必填列表字段（避免服务端 400 后再提示）。
        guard requiredFieldsFilled else {
            let missing = requiredListFields
                .filter { customFieldValues[$0.id]?.isEmpty ?? true }
                .map(\.name)
                .joined(separator: "、")
            resultText = "请填写必填字段：\(missing)"
            resultIsError = true
            return
        }

        do {
            let config = try store.buildConfiguration()
            let reporter = YunxiaoBugReporter()
            try reporter.configure(config)

            var attachments: [YXBAttachment] = []
            for (index, item) in images.enumerated() {
                if let data = item.image.jpegData(compressionQuality: 0.8) {
                    attachments.append(
                        YXBAttachment(data: data, fileName: "screenshot-\(index + 1).jpg", mimeType: "image/jpeg")
                    )
                }
            }

            let report = YXBBugReport(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description,
                format: formatRaw == "MD" ? .markdown : .plainText,
                customFields: customFieldValues,
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
        } catch {
            resultText = "提交失败：\(error.localizedDescription)"
            resultIsError = true
        }
    }
}

/// 带稳定标识的选中图片，用于 `ForEach` 与删除。
struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

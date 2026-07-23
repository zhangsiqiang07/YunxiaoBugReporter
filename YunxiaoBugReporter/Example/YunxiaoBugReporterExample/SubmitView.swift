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

    var body: some View {
        Form {
            Section("指派给") {
                HStack {
                    Text("负责人")
                    Spacer()
                    Text(assigneeDisplay)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

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
                .disabled(isSubmitting || title.trimmingCharacters(in: .whitespaces).isEmpty)
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
    }

    /// 负责人展示文案：优先显示姓名，并附上用户 ID（提交接口需要 ID）。
    private var assigneeDisplay: String {
        let id = store.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return "未配置" }
        if store.assignedToName.isEmpty {
            return id
        }
        return "\(store.assignedToName)（\(id)）"
    }

    private func submit() async {
        isSubmitting = true
        resultText = nil
        defer { isSubmitting = false }
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

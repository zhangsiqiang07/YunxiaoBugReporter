import SwiftUI

/// 云效配置页面。两种模式：
/// - `.forced`：未配置时强制展示，隐藏返回按钮，保存后回调 `onComplete` 进入主界面；
/// - `.normal`：作为 Tab 之一，可随时修改保存。
struct ConfigView: View {
    enum Mode { case normal, forced }

    let mode: Mode
    var onComplete: (() -> Void)? = nil

    @EnvironmentObject private var store: DemoConfigStore
    @State private var showErrors = false
    @State private var errorMessages: [String] = []

    var body: some View {
        Form {
            Section {
                TextField("服务域名", text: $store.domain)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                Picker("版本", selection: $store.editionRaw) {
                    Text("中心版").tag("standard")
                    Text("Region 版").tag("region")
                }
                .pickerStyle(.segmented)
                if store.editionRaw == "standard" {
                    TextField("组织 ID", text: $store.organizationID)
                }
                TextField("项目 ID", text: $store.projectID)
                TextField("负责人用户 ID", text: $store.assignedTo)
                TextField("工作项类型 ID（可选）", text: $store.workitemTypeID)
                    .textInputAutocapitalization(.never)
            } header: { Text("云效服务") } footer: {
                Text("仅「工作项类型 ID」为可选，留空时由 SDK 自动选择 Bug 类型，无需填写；其余字段均为必填。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("云效访问 Token", text: $store.token, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Token 以明文保存在 UserDefaults（仅用于演示，生产环境请勿如此）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: { Text("访问凭证") } footer: {
                Text("当前已保存的 Token 会显示在此处；留空将导致提交失败。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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

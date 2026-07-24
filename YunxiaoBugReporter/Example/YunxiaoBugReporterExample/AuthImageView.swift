import SwiftUI
import YunxiaoBugReporter

/// 通过 SDK 下载并展示工作项描述中的图片。
///
/// 描述里的图片 `src` 是云效**控制台代理地址**（`devops.aliyun.com/.../file/url?fileIdentifier=...`），
/// 与 OpenAPI 网关不同源、直接用 Token 访问会 401。因此这里优先走 `downloadWorkitemFile`
/// （经官方 `GetWorkitemFile` 换取预签名临时地址再下载）；对非控制台地址则回退到通用
/// 的 `downloadImage(at:)`。两者最终都用 `UIImage(data:)` 展示。
struct AuthImageView: View {
    let url: URL
    let workitemID: String
    let reporter: YunxiaoBugReporter

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(minHeight: 120)
            } else {
                // 失败或非图片数据：展示占位图标，并允许点击重试。
                HStack {
                    Spacer()
                    Image(systemName: didFail ? "exclamationmark.triangle.fill" : "photo.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(minHeight: 120)
                .contentShape(Rectangle())
                .onTapGesture { Task { await load() } }
            }
        }
        .task { await load() }
    }

    /// 若 `url` 是云效控制台文件代理地址，提取其 `fileIdentifier`；否则返回 nil。
    private var consoleFileIdentifier: String? {
        guard let host = url.host,
              host.contains("devops.aliyun.com"),
              url.path.contains("/projex/api/workitem/file/url"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let fid = components.queryItems?.first(where: { $0.name == "fileIdentifier" })?.value,
              !fid.isEmpty else {
            return nil
        }
        return fid
    }

    private func load() async {
        guard !isLoading else { return }
        await MainActor.run {
            isLoading = true
            didFail = false
        }
        do {
            let data: Data
            if let fid = consoleFileIdentifier, !workitemID.isEmpty {
                // 控制台代理地址：经官方 GetWorkitemFile 换取临时地址后下载。
                data = try await reporter.downloadWorkitemFile(fileIdentifier: fid, workitemID: workitemID)
            } else {
                // 其他地址（如同源 OpenAPI 资源）：直接带 Token 下载。
                data = try await reporter.downloadImage(at: url)
            }
            if UIImage(data: data) != nil {
                await MainActor.run {
                    self.image = UIImage(data: data)
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.didFail = true
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.didFail = true
                self.isLoading = false
            }
        }
    }
}

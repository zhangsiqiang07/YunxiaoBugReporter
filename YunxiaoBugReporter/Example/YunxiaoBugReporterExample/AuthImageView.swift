import SwiftUI
import YunxiaoBugReporter

/// 通过 SDK 带鉴权下载并展示图片。
///
/// 云效工作项描述中的图片地址需要 `x-yunxiao-token` 头，SwiftUI 的 `AsyncImage`
/// 无法附加自定义请求头，会直接请求失败（显示「?」占位）。因此这里改用 SDK 的
/// `downloadImage(at:)`（内部会注入 `x-yunxiao-token`）拉取二进制后再用 `UIImage` 展示。
struct AuthImageView: View {
    let url: URL
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

    private func load() async {
        guard !isLoading else { return }
        await MainActor.run {
            isLoading = true
            didFail = false
        }
        do {
            let data = try await reporter.downloadImage(at: url)
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

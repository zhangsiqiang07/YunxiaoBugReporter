# YunxiaoBugReporter

轻量级 iOS SDK（Swift 5.9，最低 iOS 15.0），用于将宿主 App 提供的 Bug 信息、截图和日志附件上报到**阿里云效（云效）Projex** 的 Bug 工作项。

> 适用场景：内部工具、Debug 构建或受控分发场景的直连上报。
> ⚠️ **不建议把个人访问令牌硬编码在正式 App 中**。生产环境建议后续通过内部 Gateway 中转上报（见「Token 安全警告」与「版本规划」）。

---

## 1. 功能介绍

- 查询项目下的 Bug 工作项类型，并在未显式配置 `workitemTypeID` 时自动选择：
  - `category` 为 Bug 且 `enabled` 为 true；
  - 优先 `default` 为 true 的类型；
  - 若没有默认类型，选择第一个启用的类型。
- 创建云效 Bug 工作项。
- 将宿主传入的图片、文本、日志或其他文件以 `multipart/form-data` 上传为工作项附件。
- 返回 Bug ID、附件上传结果与整体提交状态；附件部分失败时返回 `partialSuccess` 而非抛错。
- 网络层基于 `URLSession` + `async/await`，**不依赖 Alamofire**，除 `Foundation` 外不引入其他系统框架。
- **SDK 本身不包含任何 UI**，也不负责截图采集、截图标注、Crash 捕获或网络日志采集——这些数据由宿主 App 提供。

所有公开类型使用 `YXB` 前缀，统一位于 `YunxiaoBugReporter` Module。

---

## 2. CocoaPods 安装

```ruby
# Podfile
platform :ios, '15.0'
use_frameworks!

target 'YourApp' do
  pod 'YunxiaoBugReporter', :path => '../YunxiaoBugReporter'
end
```

然后执行：

```bash
pod install
```

> 本地开发使用 `:path` 方式即可。发布时改用版本 tag：
> ```ruby
> pod 'YunxiaoBugReporter', '~> 0.1.0'
> ```

### 运行自带 Example

仓库内 `Example/` 是一个最小可运行的演示 App，采用 **SwiftUI**（最低 iOS 16.0），界面贴合 Apple HIG：

- 启动后只有一个 **「进入」** 落地页（Landing）；
- 若尚未配置云效信息，**每次进入都会先跳转到「云效配置」页**（强制配置，无法返回跳过）；
- 配置完成后进入主界面，包含 **「提交 Bug」** 与 **「云效配置」** 两个 Tab；
- Token 保存在 **钥匙串（Keychain）**，不以明文写入代码或 `UserDefaults`；
- 配置页可选开启 **结果缓存**（内存 / UserDefaults 两种后端，可分别设置 TTL）。

> SDK 自身仍支持 iOS 15.0+；仅 Example 演示 App 因使用了 `NavigationStack` 等 iOS 16 API，要求 iOS 16.0+。

运行方式：

```bash
cd Example
pod install
open YunxiaoBugReporterExample.xcworkspace   # 必须用 workspace 打开，而非 .xcodeproj
```

打开后，在「云效配置」中填写：服务域名、版本（中心版 / Region 版）、组织 ID（中心版必填）、项目 ID、负责人用户 ID、访问 Token；保存后回到「提交 Bug」即可填写标题/描述、选择截图并一键上报。

- `Example/Pods/` 与 `*.xcworkspace` 已纳入 `.gitignore`；仅 `YunxiaoBugReporterExample.xcodeproj` 入库。
- `YunxiaoBugReporterExample.xcodeproj` 由生成脚本重新产出；向 Example 新增/删除 Swift 源文件后，需重新执行 `pod install` 让 Pods 工程重新集成。

---

## 3. 初始化配置

```swift
import YunxiaoBugReporter

let reporter = YunxiaoBugReporter()

let config = YXBConfiguration(
    domain: "https://your-yunxiao-domain.com",   // 必须为 http/https
    edition: .standard,                           // .standard 或 .region
    organizationID: "your-organization-id",       // 中心版必填
    projectID: "your-project-id",
    assignedTo: "assignee-user-id",
    tokenProvider: {
        // SDK 不持久化 Token，每次需要时才调用该闭包
        try await loadTokenFromSecureStore()
    }
)

do {
    try reporter.configure(config)
} catch {
    // 配置不合法（如 domain 非 http(s)、中心版缺少 organizationID 等）
    print("配置失败: \(error)")
}
```

`tokenProvider` 是一个 `@Sendable () async throws -> String` 闭包，SDK 不会保存 Token。

### 3.1 结果缓存（可选）

默认**不缓存**。配置 `YXBConfiguration.cache` 后，SDK 会缓存两类派生结果，以减少对云效 API 与 `tokenProvider` 的重复调用：

- **工作项类型**：当未显式指定 `workitemTypeID` 时，首次提交会查询 Bug 类型并自动选中，结果按 `(edition, organizationID, projectID)` 作为键写入缓存，TTL 由 `workitemTypeCacheTTL`（默认 3600 秒）控制；后续提交直接命中缓存，不再调用 `workitemTypes` 接口。
- **Token**：在 `tokenCacheTTL > 0`（默认 300 秒）且 `cache` 非 `nil` 时，Token 写入缓存，TTL 内重复提交复用，不再调用 `tokenProvider`。

缓存后端需遵循 `YXBCache` 协议（`Sendable`、`async` 且非 `throws`，读取失败静默降级为主流程）。SDK 内置两种实现：

```swift
import YunxiaoBugReporter

// 方案 A：内存缓存（进程级，推荐用于缓存 Token，明文不落盘）
let config = YXBConfiguration(
    domain: "...",
    edition: .standard,
    organizationID: "...",
    projectID: "...",
    assignedTo: "...",
    tokenProvider: { try await loadToken() },
    cache: YXBInMemoryCache(),   // 启用缓存
    workitemTypeCacheTTL: 3600,  // 工作项类型缓存 1 小时
    tokenCacheTTL: 300           // Token 缓存 5 分钟（<=0 则不缓存 Token）
)

// 方案 B：UserDefaults 缓存（可跨启动复用，适合缓存非敏感的工作项类型）
let config2 = YXBConfiguration(
    domain: "...",
    edition: .standard,
    organizationID: "...",
    projectID: "...",
    assignedTo: "...",
    tokenProvider: { try await loadToken() },
    cache: YXBUserDefaultsCache(suiteName: "com.yourapp.yunxiao"),
    workitemTypeCacheTTL: 86400,
    tokenCacheTTL: 0             // 不缓存 Token（避免明文落盘）
)
```

安全提示：Token 是敏感凭证。**不建议**将 Token 缓存到 `YXBUserDefaultsCache`（明文落盘，存在越狱/备份提取风险）。缓存 Token 时请使用 `YXBInMemoryCache`；若必须采用 `UserDefaults` 后端，请确保运行环境受控（如企业内部托管设备），且不要写入高权限 Token。工作项类型属非敏感派生数据，适合持久化。

自定义后端只需实现 `YXBCache` 协议（例如 Keychain、文件、LRU 内存等），即可注入 `cache` 字段。

---

## 4. 提交纯文本 Bug

```swift
let report = YXBBugReport(
    title: "点击登录按钮崩溃",
    description: "在 iPhone 15 Pro / iOS 17 上复现率 100%",
    format: .plainText,                // 或 .markdown
    customFields: ["priority": "P0"],
    labels: ["crash", "login"]
)

Task {
    do {
        let result = try await reporter.submit(report)
        print("workitemID = \(result.workitemID), status = \(result.status)")
    } catch {
        print("提交失败: \(error)")
    }
}
```

---

## 5. 提交带截图 Bug

SDK 不依赖 `UIImage`，只接收 `Data`。宿主负责把截图转成 `Data`：

```swift
// 假设 image 为 UIImage
guard let pngData = image.pngData() else { return }

let attachment = YXBAttachment(
    data: pngData,
    fileName: "screenshot.png",
    mimeType: "image/png"
)

let report = YXBBugReport(
    title: "支付页白屏",
    description: "见附件截图",
    attachments: [attachment]
)

let result = try await reporter.submit(report)
```

---

## 6. 中心版与 Region 版区别

通过 `YXBConfiguration.Edition` 区分，URL 构造不同：

| 能力 | 中心版 `.standard` | Region 版 `.region` |
| --- | --- | --- |
| 组织 ID | **必填** | 忽略 |
| 查询类型 | `/oapi/v1/projex/organizations/{org}/projects/{proj}/workitemTypes?category=Bug` | `/oapi/v1/projex/projects/{proj}/workitemTypes?category=Bug` |
| 创建工作项 | `/oapi/v1/projex/organizations/{org}/workitems` | `/oapi/v1/projex/workitems` |
| 上传附件 | `/oapi/v1/projex/organizations/{org}/workitems/{id}/attachments` | `/oapi/v1/projex/workitems/{id}/attachments` |

所有请求通过 Header `x-yunxiao-token` 传递 Token；创建工作项使用 `application/json`，附件上传使用 `multipart/form-data`（字段名固定为 `file`，由 SDK 生成随机 boundary）。

---

## 7. 自定义字段使用方式

把自定义字段放入 `YXBBugReport.customFields`（键为云效字段 Key，值为字符串），SDK 会编码为请求体的 `customFieldValues`：

```swift
let report = YXBBugReport(
    title: "列表滑动卡顿",
    description: "帧率低于 30fps",
    customFields: [
        "module": "feed",
        "priority": "P1",
        "env": "production"
    ]
)
```

> 字段 Key 需与你在云效工作项类型中定义的自定义字段 Key 一致。

---

## 8. Token 安全警告

- **不要**将个人访问令牌硬编码进源码或打包进正式 App。
- 直连云效适合**内部、Debug 或受控分发**场景。
- 建议通过 `tokenProvider` 从安全存储（Keychain / 内部服务）动态获取 Token，SDK 不负责持久化。
- **生产环境建议后续通过内部 Gateway 上报**：由 Gateway 持有云效凭据，App 只与自有后端通信，避免令牌下发到客户端。
- SDK 的日志与错误信息**不会**输出 Token、完整附件二进制或含用户隐私的完整请求体。

### 8.1 请求日志（默认开启）

SDK 在传输层（`YXBHTTPClient`）**统一记录每一个 HTTP 请求**，无需额外配置：

- 请求：`→ POST https://.../workitems headers={ ... x-yunxiao-token: <redacted> ... } body=1234 bytes`
- 成功响应：`← 201 https://.../workitems（耗时 0.34s，512 bytes）`
- 失败响应：`← 401 https://.../workitems（耗时 0.12s）：<云效返回 message>`

默认日志器为内置的 `YXBOSLogger`（基于 `os.log`，子系统 `com.yunxiao.bugreporter`），当 `YXBConfiguration.logger` 为 `nil` 时自动启用——即**开箱即用，所有请求均有日志**。

**Token 头安全**：`x-yunxiao-token` 在任何日志中一律以 `<redacted>` 输出，不会泄露。

自定义 / 关闭：

```swift
// 1) 使用内置日志器（默认行为，可省）
var config = YXBConfiguration(...)
config.logger = YXBOSLogger()           // os.log 输出

// 2) 注入自己的日志器（如接入自有上报系统）
config.logger = MyAppLogger()          // 遵循 YXBLogger 协议

// 3) 显式关闭所有日志
config.logger = YXBNoOpLogger()
```

> 日志协议 `YXBLogger` 与级别 `YXBLogLevel`（debug / info / warn / error）均为公开的，宿主可实现后注入。

---

## 9. 错误处理

`submit` 仅在以下情况抛错（`YXBError`）；只要工作项创建成功，即使附件失败也会返回结果（见第 10 节）：

- `.notConfigured`：未配置。
- `.invalidConfiguration(String)`：配置校验失败。
- `.invalidReport(String)`：报告校验失败（如 title 为空、附件为空/缺字段）。
- `.tokenUnavailable(String)`：`tokenProvider` 抛错。
- `.workitemTypeNotFound`：未找到可用的 Bug 类型。
- `.workitemCreationFailed(String)`：创建工作项失败。
- `.httpError(statusCode:message:)`：HTTP 非 2xx（含解析出的 message/code/requestId）。
- `.decodingFailed(String)` / `.invalidResponse` / `.underlying(String)` / `.attachmentTooLarge(fileName:limit:)`。

> 超过大小限制（默认 20 MB）的附件会触发报告级校验失败（`attachmentTooLarge`），在创建工作项之前即抛错；运行时上传失败（网络/服务端）才会进入 `partialSuccess` 逻辑。

---

## 10. 部分附件失败的处理方式

当工作项创建成功后，SDK 会并发上传所有附件（并发数由 `maximumConcurrentUploads` 控制，默认 2，范围 1...4）：

- 单个附件上传失败**不会影响**其他附件；
- 返回结果按输入附件顺序排列；
- 只要有任一附件失败，整体状态为 `.partialSuccess`；
- **工作项不会被重复创建**（创建成功后才会上传附件）。

```swift
let result = try await reporter.submit(report)
switch result.status {
case .success:
    print("全部成功")
case .partialSuccess:
    print("工作项已创建，但 \(result.failedAttachments.count) 个附件失败")
    for failed in result.failedAttachments {
        print("失败附件: \(failed.fileName), 原因: \(String(describing: failed.error))")
    }
}
```

---

## 11. 当前不包含的能力

首期 deliberately 不包含以下内容，由宿主 App 负责：

- 截图采集（系统相册 / 屏幕截图）；
- 截图标注 / 涂鸦；
- Crash 捕获与符号化；
- 网络日志自动采集；
- 任何 UI 组件。

---

## 12. 版本规划

- **0.1.0（当前）**：核心上报链路、中心版/Region 版、Mock 可测、CocoaPods 集成、基础错误与日志。
- **后续**：
  - 支持通过内部 Gateway 上报（推荐用于生产环境，避免客户端持有令牌）；
  - 工作项类型字段读取与自定义字段 UI 辅助；
  - 更细粒度的重试与断点续传策略；
  - 可选的内置日志采集适配层（仍由宿主触发）。

---

## 许可证

MIT

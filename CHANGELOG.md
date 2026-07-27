# Changelog

所有重要变更记录于此文件。格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本遵循 [SemVer](https://semver.org/)。

## [0.1.0] - 2026-07-22

### 新增
- 初始版本：通过 CocoaPods 集成的 iOS Swift SDK，用于向阿里云效（云效）Projex 上报 Bug 工作项。
- 云效 API 支持中心版（`.standard`）与 Region 版（`.region`）URL 构造。
- 查询项目下的 Bug 工作项类型，未显式配置 `workitemTypeID` 时按规则自动选择默认/首个启用类型。
- 创建工作项（JSON 编码，含 `customFieldValues`、`labels` 等）。
- 以 `multipart/form-data` 上传附件，随机 boundary，`name="file"`，有限并发上传（`maximumConcurrentUploads`，默认 2，范围 1...4）。
- 完整提交编排：只要工作项创建成功，附件部分失败返回 `.partialSuccess`，不重复创建 Bug。
- `async/await` + `URLSession` 网络层，无第三方网络库依赖。
- 可注入的 `YXBTransport` 协议，便于 Mock 测试；附带 22 个 XCTest 用例（URL 构造、Header、JSON 编码、类型选择、multipart、提交链路、错误与日志安全等）。
- 可选 `YXBLogger` 日志协议，覆盖关键步骤，且保证不输出 Token / 完整附件二进制 / 敏感请求体。
- 结构化 `YXBError`（满足 Swift 严格并发 `Sendable` 要求，关联值统一为 String）。
- 最小 Example 演示工程（占位符配置 + 相册选图 + 提交），不写入真实 Token。

### 安全
- 不在源码、Demo、测试或 README 中写入任何真实云效 Token 或账号信息。
- Token 通过 `tokenProvider` 异步闭包获取，SDK 不持久化。

### 已知限制
- 单附件默认大小上限 20 MB（内部常量 `YXBConstants.maxAttachmentBytes`）；超限会触发报告级校验失败并抛错。
- 「部分附件失败返回 partialSuccess」针对上传阶段的运行时失败；超出大小限制的附件会在创建工作项前被拒绝。

import Foundation

/// 演示用「几乎不变」的配置项，直接写死在代码中。
///
/// 这些值极少变更，默认填充并自动展示于配置页，无需手动输入。
/// 若需变更，直接修改这里的常量即可。
///
/// ⚠️ 生产环境请勿将 Token 明文写死在代码里，应从安全存储（钥匙串等）读取。
enum DemoConstants {
    /// 云效服务域名。
    static let domain = "https://openapi-rdc.aliyuncs.com"

    /// 组织 ID（中心版必填）。
    static let organizationID = "YOUR_ORG_ID"

    /// 云效访问 Token。明文写死仅用于演示。
    /// TODO: 替换为你的实际云效访问 Token。
    static let token = "YOUR_YUNXIAO_TOKEN"
}

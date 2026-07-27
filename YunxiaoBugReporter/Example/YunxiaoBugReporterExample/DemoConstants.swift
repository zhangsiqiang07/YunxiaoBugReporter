import Foundation

/// 演示用「几乎不变」的配置项，直接写死在代码中。
///
/// 这些值极少变更，默认填充并自动展示于配置页，无需手动输入。
/// 若需变更，直接修改这里的常量即可。
///
/// ⚠️ 生产环境请勿将 Token 明文写死在代码里，应从安全存储（钥匙串等）读取。
///
/// 🔒 安全说明：本文件提交到仓库的 `organizationID` / `token` 均为占位符
///（`YOUR_ORG_ID` / `YOUR_YUNXIAO_TOKEN`）。开发者在本机用**真实值**覆盖后，
/// 执行 `git update-index --skip-worktree <本文件>` 将其标记为「本地改动不纳入提交」，
/// 从而本地可正常联网运行，而真实凭据永远不会进入 git 历史或被推送。
/// 若需拉取上游对此文件的占位符更新，先 `git update-index --no-skip-worktree <本文件>`
/// 解除标记，再 `git checkout -- <本文件>` 取回上游占位符，最后重新填入真实值并 skip-worktree。
enum DemoConstants {
    /// 云效服务域名。
    static let domain = "https://openapi-rdc.aliyuncs.com"

    /// 组织 ID（中心版必填）。
    static let organizationID = "YOUR_ORG_ID"

    /// 云效访问 Token。明文写死仅用于演示。
    /// TODO: 替换为你的实际云效访问 Token。
    static let token = "YOUR_YUNXIAO_TOKEN"
}

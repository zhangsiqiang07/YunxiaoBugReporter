import Foundation
import Security
import YunxiaoBugReporter

/// 演示用 Token 存储。Token 属于敏感凭证，存放在 iOS 钥匙串（Keychain），
/// 而非代码或明文 `UserDefaults`。本类为无状态枚举，可在任意线程安全调用。
enum KeychainStore {
    static let service = "com.yunxiao.demo"
    static let account = "yunxiao.token"

    /// 是否存在已保存的 Token。
    static var hasToken: Bool {
        (try? readToken()) != nil
    }

    /// 保存 Token（覆盖式写入）。
    static func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        // 先删除旧值，再新增，避免 duplicate item 错误。
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// 读取 Token。不存在或为空时抛出，供 SDK 转换为 `YXBError.tokenUnavailable`。
    static func readToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              token.isEmpty == false else {
            throw YXBError.tokenUnavailable("Token 未配置，请先在配置页填写")
        }
        return token
    }

    /// 删除 Token。
    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

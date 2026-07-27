import Foundation

/// 可插拔缓存后端协议。SDK 用它缓存「解析出的工作项类型」与「Token」，
/// 以减少对云效 API 与 `tokenProvider` 的重复调用。
///
/// 设计约束：
/// - 所有方法均为 `async` 且**非 `throws`**；缓存读取/写入失败应静默降级（读取返回 `nil`，写入忽略），
///   绝不影响主流程；
/// - 实现必须 `Sendable`（`actor` 或带内部锁的类均可）；
/// - 仅在 `YXBConfiguration.cache` 非 `nil` 时启用缓存。
public protocol YXBCache: Sendable {
    /// 读取字符串值；不存在或已过期返回 `nil`。
    func string(forKey key: String) async -> String?

    /// 写入字符串值。
    /// - Parameters:
    ///   - value: 待缓存值。
    ///   - key: 键。
    ///   - ttl: 存活秒数；`nil` 或 `<= 0` 表示永不过期。
    func setString(_ value: String, forKey key: String, ttl: TimeInterval?) async

    /// 删除指定键的缓存值（用于 Token 失效时主动失效，避免复用旧凭证）。
    /// 实现应仅删除该键对应的值与附属过期标记，不影响其它键。
    func remove(forKey key: String) async
}

// MARK: - 内存缓存（默认，进程级安全）

/// 进程内内存缓存。无持久化，App 重启即清空。
///
/// 适用于缓存 Token（明文仅驻留内存，不落盘），也适用于缓存工作项类型。
public actor YXBInMemoryCache: YXBCache {
    private struct Entry {
        let value: String
        let expiresAt: Date?
    }

    private var store: [String: Entry] = [:]

    public init() {}

    public func string(forKey key: String) async -> String? {
        guard let entry = store[key] else { return nil }
        if let expiresAt = entry.expiresAt, expiresAt <= Date() {
            store[key] = nil
            return nil
        }
        return entry.value
    }

    public func setString(_ value: String, forKey key: String, ttl: TimeInterval?) async {
        let expiresAt: Date?
        if let ttl = ttl, ttl > 0 {
            expiresAt = Date().addingTimeInterval(ttl)
        } else {
            expiresAt = nil
        }
        store[key] = Entry(value: value, expiresAt: expiresAt)
    }

    /// 清空全部缓存（测试或主动失效用）。
    public func removeAll() async {
        store.removeAll()
    }

    public func remove(forKey key: String) async {
        store.removeValue(forKey: key)
    }
}

// MARK: - UserDefaults 缓存（可跨启动复用）

/// 基于 `UserDefaults` 的缓存。可跨 App 启动复用。
///
/// ⚠️ 安全提示：Token 是敏感凭证。**不建议**将 Token 缓存到 `UserDefaults`
/// （明文落盘，易被越狱/备份提取）。缓存 Token 时请优先使用 `YXBInMemoryCache`；
/// 若确实要用 `YXBUserDefaultsCache`，请确保仅在安全的分发场景（如企业内部托管设备）使用，
/// 且不要把高权限 Token 写入其中。工作项类型属非敏感派生数据，适合持久化。
public actor YXBUserDefaultsCache: YXBCache {
    private let defaults: UserDefaults
    private let expirySuffix = ".yxb.expiry"
    /// 本 SDK 写入键的统一前缀，用于 `removeAll` 隔离清理，避免误删宿主 App 其它数据。
    static let keyPrefix = "yxb."

    public init(suiteName: String? = nil) {
        if let suiteName = suiteName, let suite = UserDefaults(suiteName: suiteName) {
            self.defaults = suite
        } else {
            self.defaults = .standard
        }
    }

    public func string(forKey key: String) async -> String? {
        let fullKey = Self.keyPrefix + key
        if let expiryString = defaults.string(forKey: fullKey + expirySuffix),
           let expiresAt = ISO8601DateFormatter().date(from: expiryString),
           expiresAt <= Date() {
            defaults.removeObject(forKey: fullKey)
            defaults.removeObject(forKey: fullKey + expirySuffix)
            return nil
        }
        return defaults.string(forKey: fullKey)
    }

    public func setString(_ value: String, forKey key: String, ttl: TimeInterval?) async {
        let fullKey = Self.keyPrefix + key
        defaults.set(value, forKey: fullKey)
        if let ttl = ttl, ttl > 0 {
            let expiresAt = Date().addingTimeInterval(ttl)
            defaults.set(ISO8601DateFormatter().string(from: expiresAt), forKey: fullKey + expirySuffix)
        } else {
            defaults.removeObject(forKey: fullKey + expirySuffix)
        }
    }

    /// 仅清空本 SDK 前缀（`yxb.`）的键，不影响宿主 App 其它 `UserDefaults` 数据。
    public func removeAll() async {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    public func remove(forKey key: String) async {
        let fullKey = Self.keyPrefix + key
        defaults.removeObject(forKey: fullKey)
        defaults.removeObject(forKey: fullKey + expirySuffix)
    }
}

import XCTest
@testable import YunxiaoBugReporter

/// 验证缓存后端（内存 / UserDefaults）与过期语义。
final class YXBCacheTests: XCTestCase {

    // MARK: - 内存缓存

    func testInMemoryCacheStoresAndReads() async {
        let cache = YXBInMemoryCache()
        await cache.setString("v1", forKey: "k1", ttl: nil)
        let value = await cache.string(forKey: "k1")
        XCTAssertEqual(value, "v1")
    }

    func testInMemoryCacheMissReturnsNil() async {
        let cache = YXBInMemoryCache()
        let value = await cache.string(forKey: "missing")
        XCTAssertNil(value)
    }

    func testInMemoryCacheExpiry() async {
        let cache = YXBInMemoryCache()
        // ttl = -1 表示永不过期；这里用极短正 TTL 后会过期。
        await cache.setString("v", forKey: "exp", ttl: 0.01)
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        let value = await cache.string(forKey: "exp")
        XCTAssertNil(value, "过期后读取应返回 nil")
    }

    func testInMemoryCacheOverwrite() async {
        let cache = YXBInMemoryCache()
        await cache.setString("a", forKey: "x", ttl: nil)
        await cache.setString("b", forKey: "x", ttl: nil)
        let value = await cache.string(forKey: "x")
        XCTAssertEqual(value, "b")
    }

    // MARK: - UserDefaults 缓存

    func testUserDefaultsCacheRoundTrip() async {
        let cache = YXBUserDefaultsCache(suiteName: "com.yunxiao.test.cache")
        await cache.removeAll()
        await cache.setString("persisted", forKey: "cfg", ttl: nil)
        let value = await cache.string(forKey: "cfg")
        XCTAssertEqual(value, "persisted")
        await cache.removeAll()
        let afterClear = await cache.string(forKey: "cfg")
        XCTAssertNil(afterClear)
    }

    func testUserDefaultsCacheExpiry() async {
        let cache = YXBUserDefaultsCache(suiteName: "com.yunxiao.test.cache")
        await cache.removeAll()
        await cache.setString("v", forKey: "e", ttl: 0.01)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let expired = await cache.string(forKey: "e")
        XCTAssertNil(expired)
        await cache.removeAll()
    }

    func testUserDefaultsCacheIsolatedFromForeignKeys() async {
        let cache = YXBUserDefaultsCache(suiteName: "com.yunxiao.test.cache")
        await cache.removeAll()
        // 宿主 App 自己的键不应被 removeAll 清理。
        let defaults = UserDefaults(suiteName: "com.yunxiao.test.cache")!
        defaults.set("host-value", forKey: "host.own.key")
        await cache.removeAll()
        XCTAssertEqual(defaults.string(forKey: "host.own.key"), "host-value")
        await cache.removeAll()
    }
}

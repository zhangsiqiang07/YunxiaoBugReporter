import Foundation

/// Bug 工作项类型选择规则。
enum YXBWorkitemTypeSelector {
    /// 从可用类型中选出目标 Bug 类型。
    ///
    /// 规则：
    /// 1. 过滤出 category 为 Bug 且 enabled 为 true 的类型；
    /// 2. 优先选择 `isDefault` 为 true 的类型；
    /// 3. 若无默认类型，选择第一个启用的类型；
    /// 4. 都没有则返回 `nil`（调用方应抛出 `YXBError.workitemTypeNotFound`）。
    static func select(from types: [YXBWorkitemType]) -> YXBWorkitemType? {
        let bugTypes = types.filter { type in
            let category = (type.category ?? "Bug").trimmingCharacters(in: .whitespacesAndNewlines)
            let isBug = category.caseInsensitiveCompare("Bug") == .orderedSame
            return isBug && type.enabled
        }
        if let `default` = bugTypes.first(where: { $0.isDefault }) {
            return `default`
        }
        return bugTypes.first
    }
}

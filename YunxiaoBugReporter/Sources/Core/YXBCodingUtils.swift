import Foundation

/// 通用 `CodingKey`，用于在解码响应时按动态字符串键取值。
/// 云效不同接口的返回字段名不完全一致，这里提供灵活的按 Key 取值能力。
struct YXBAnyCodingKey: CodingKey, Sendable {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

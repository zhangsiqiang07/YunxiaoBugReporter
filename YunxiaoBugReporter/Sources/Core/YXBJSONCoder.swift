import Foundation

/// JSON 编解码器。集中配置 encoder / decoder，避免在多处重复创建。
enum YXBJSONCoder {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // 排序键，便于调试与测试断言稳定；不转义斜杠，保持 URL 友好。
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        JSONDecoder()
    }()
}

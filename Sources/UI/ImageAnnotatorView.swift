import SwiftUI

/// 全屏图片标注器：在截图上拖拽绘制红色矩形框。
///
/// 设计要点：
/// - 图片以 `.scaledToFit` 居中显示（letterbox），拖拽坐标映射到图片自然尺寸并**归一化（0..1）**存储，
///   这样无论后续缩放在何种容器、是否上传，框选位置都保持稳定、可复现。
/// - `onDone` 返回归一化矩形（相对图片自然尺寸）；用户「清除」后返回 `nil`。
/// - 兼容 iOS 15：仅使用 `DragGesture` / `GeometryReader` / `UIGraphicsImageRenderer`（iOS 10+），
///   不使用 `NavigationStack` 及任何 `.toolbar` 顶层控制流等 iOS 16 专属 API。
struct ImageAnnotatorView: View {
    let image: UIImage
    var initialRect: CGRect?
    var onDone: (CGRect?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var committed: CGRect?

    init(image: UIImage, initialRect: CGRect? = nil, onDone: @escaping (CGRect?) -> Void) {
        self.image = image
        self.initialRect = initialRect
        self.onDone = onDone
        _committed = State(initialValue: initialRect)
    }

    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                let container = proxy.size
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    annotationOverlay(container: container)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(container: container))
            }
            .navigationTitle("框选标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: { Text("取消") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { clear() } label: { Text("清除") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { finish() } label: { Text("完成").bold() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 拖拽手势

    private func dragGesture(container: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                defer { dragStart = nil; dragCurrent = nil }
                guard let start = dragStart else { return }
                let current = value.location
                let width = abs(current.x - start.x)
                let height = abs(current.y - start.y)
                // 忽略过小（误触）的拖拽。
                guard width > 4, height > 4 else { return }
                let raw = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: width,
                    height: height
                )
                committed = Self.toNormalized(raw, container: container, imageSize: image.size)
            }
    }

    // MARK: - 覆盖层（红色矩形）

    @ViewBuilder
    private func annotationOverlay(container: CGSize) -> some View {
        if let rect = displayRect(container: container) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.red, lineWidth: 3)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private func displayRect(container: CGSize) -> CGRect? {
        if let start = dragStart, let current = dragCurrent {
            let raw = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            let clipped = raw.intersection(Self.contentRect(container: container, image: image.size))
            return clipped.isEmpty ? nil : clipped
        }
        if let committed = committed {
            return Self.fromNormalized(committed, container: container, imageSize: image.size)
        }
        return nil
    }

    // MARK: - 交互

    private func clear() {
        committed = nil
    }

    private func finish() {
        onDone(committed)
    }

    // MARK: - 坐标换算

    /// 计算 `scaledToFit` 下图片在容器内的实际绘制区域（可能 letterbox）。
    private static func contentRect(container: CGSize, image: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / image.width, container.height / image.height)
        let w = image.width * scale
        let h = image.height * scale
        return CGRect(
            x: (container.width - w) / 2,
            y: (container.height - h) / 2,
            width: w,
            height: h
        )
    }

    /// 容器内坐标（scaledToFit）矩形 → 归一化（0..1，相对图片自然尺寸），并裁剪到图片范围。
    private static func toNormalized(_ rect: CGRect, container: CGSize, imageSize: CGSize) -> CGRect {
        let content = contentRect(container: container, image: imageSize)
        let clipped = rect.intersection(content)
        guard !clipped.isEmpty else { return .zero }
        let x = (clipped.origin.x - content.origin.x) / content.width
        let y = (clipped.origin.y - content.origin.y) / content.height
        let w = clipped.width / content.width
        let h = clipped.height / content.height
        return CGRect(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1),
            width: min(max(w, 0), 1),
            height: min(max(h, 0), 1)
        )
    }

    /// 归一化矩形 → 容器内坐标（scaledToFit）。
    private static func fromNormalized(_ normalized: CGRect, container: CGSize, imageSize: CGSize) -> CGRect {
        let content = contentRect(container: container, imageSize: imageSize)
        return CGRect(
            x: content.origin.x + normalized.origin.x * content.width,
            y: content.origin.y + normalized.origin.y * content.height,
            width: normalized.width * content.width,
            height: normalized.height * content.height
        )
    }
}

/// 把归一化矩形绘制为红色描边，烘焙进图片（用于上传附件）。
///
/// - Parameters:
///   - image: 原图。
///   - normalizedRect: 归一化矩形（0..1，相对图片自然尺寸）；为 `nil` 时直接返回原图。
/// - Returns: 带红色框选的 JPEG 原图尺寸副本（绘制失败则回退原图）。
func yxb_bakeRedBox(into image: UIImage, normalizedRect: CGRect?) -> UIImage {
    guard let rect = normalizedRect,
          rect.width > 0, rect.height > 0,
          let cg = image.cgImage else {
        return image
    }
    let size = image.size
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
        let box = CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        let path = UIBezierPath(rect: box)
        UIColor.red.setStroke()
        path.lineWidth = max(size.width * 0.012, 4)
        path.stroke()
    }
}

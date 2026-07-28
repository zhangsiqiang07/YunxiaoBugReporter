import SwiftUI

/// 图片标注：红框 或 红箭头，坐标均为归一化（0..1，相对图片自然尺寸的内容绘制区）。
struct ImageAnnotation: Identifiable {
    let id = UUID()
    var kind: Kind
    /// 归一化坐标（0..1，相对图片内容绘制区）。
    /// - rect：start=左上角、end=右下角（均落在 0..1，end ≥ start）；
    /// - arrow：start=箭头尾、end=箭头头（可负向，保留方向）。
    var start: CGPoint
    var end: CGPoint

    enum Kind: String { case rect, arrow }
}

/// 红色箭头路径（仅几何，不含样式），供 SwiftUI 预览与缩略图复用。
func yxb_arrowPath(from: CGPoint, to: CGPoint) -> Path {
    var path = Path()
    path.move(to: from)
    path.addLine(to: to)
    let angle = atan2(to.y - from.y, to.x - from.x)
    let head: CGFloat = 12
    let a1 = angle + CGFloat(Double.pi / 7)
    let a2 = angle - CGFloat(Double.pi / 7)
    path.move(to: to)
    path.addLine(to: CGPoint(x: to.x - head * CGFloat(cos(a1)), y: to.y - head * CGFloat(sin(a1))))
    path.move(to: to)
    path.addLine(to: CGPoint(x: to.x - head * CGFloat(cos(a2)), y: to.y - head * CGFloat(sin(a2))))
    return path
}

/// 全屏图片标注器：支持「红框框选」与「红色箭头指向」两种标注。
///
/// - 图片以 `.scaledToFit` 居中显示（letterbox），坐标映射到图片内容区并**归一化（0..1）**存储，
///   任意缩放/上传都稳定、可复现。
/// - `onDone` 返回归一化标注数组（相对图片内容绘制区）；「清除」后返回空数组。
/// - 兼容 iOS 15：仅使用 `DragGesture` / `GeometryReader` / `UIGraphicsImageRenderer`（iOS 10+），
///   不使用 `NavigationStack` 及任何 `.toolbar` 顶层控制流等 iOS 16 专属 API。
struct ImageAnnotatorView: View {
    let image: UIImage
    var initialAnnotations: [ImageAnnotation]
    var onDone: ([ImageAnnotation]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tool: ImageAnnotation.Kind = .rect
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var committed: [ImageAnnotation] = []

    init(image: UIImage, initialAnnotations: [ImageAnnotation] = [], onDone: @escaping ([ImageAnnotation]) -> Void) {
        self.image = image
        self.initialAnnotations = initialAnnotations
        self.onDone = onDone
        _committed = State(initialValue: initialAnnotations)
    }

    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                let container = proxy.size
                ZStack {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                        annotationsOverlay(container: container)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(container: container))

                    VStack {
                        Picker("工具", selection: $tool) {
                            Text("框选").tag(ImageAnnotation.Kind.rect)
                            Text("箭头").tag(ImageAnnotation.Kind.arrow)
                        }
                        .pickerStyle(.segmented)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 12)
                }
            }
            .navigationTitle("图片标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: { Text("取消") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { undo() } label: { Text("撤销") }
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
                if tool == .rect {
                    let raw = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: width,
                        height: height
                    )
                    let norm = Self.rectToNormalized(raw, container: container, imageSize: image.size)
                    committed.append(
                        ImageAnnotation(
                            kind: .rect,
                            start: CGPoint(x: norm.minX, y: norm.minY),
                            end: CGPoint(x: norm.maxX, y: norm.maxY)
                        )
                    )
                } else {
                    let s = Self.pointToNormalized(start, container: container, imageSize: image.size)
                    let e = Self.pointToNormalized(current, container: container, imageSize: image.size)
                    committed.append(ImageAnnotation(kind: .arrow, start: s, end: e))
                }
            }
    }

    // MARK: - 覆盖层（红色矩形 / 箭头）

    @ViewBuilder
    private func annotationsOverlay(container: CGSize) -> some View {
        ForEach(committed) { ann in
            annotationShape(ann, container: container)
        }
        if let start = dragStart, let current = dragCurrent {
            let raw = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            let clipped = raw.intersection(Self.contentRect(container: container, image: image.size))
            if !clipped.isEmpty {
                if tool == .rect {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.red, lineWidth: 3)
                        .frame(width: clipped.width, height: clipped.height)
                        .position(x: clipped.midX, y: clipped.midY)
                } else {
                    let s = Self.pointToNormalized(start, container: container, imageSize: image.size)
                    let e = Self.pointToNormalized(current, container: container, imageSize: image.size)
                    let sc = Self.normalizedToPoint(s, container: container, imageSize: image.size)
                    let ec = Self.normalizedToPoint(e, container: container, imageSize: image.size)
                    yxb_arrowPath(from: sc, to: ec)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    @ViewBuilder
    private func annotationShape(_ ann: ImageAnnotation, container: CGSize) -> some View {
        let s = Self.normalizedToPoint(ann.start, container: container, imageSize: image.size)
        let e = Self.normalizedToPoint(ann.end, container: container, imageSize: image.size)
        if ann.kind == .rect {
            let r = CGRect(
                x: min(s.x, e.x),
                y: min(s.y, e.y),
                width: abs(e.x - s.x),
                height: abs(e.y - s.y)
            )
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.red, lineWidth: 3)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
        } else {
            yxb_arrowPath(from: s, to: e)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - 交互

    private func undo() {
        if !committed.isEmpty { committed.removeLast() }
    }

    private func clear() {
        committed.removeAll()
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

    /// 容器内坐标（scaledToFit）矩形 → 归一化（0..1，相对图片内容区），裁剪并夹紧到图片范围。
    private static func rectToNormalized(_ rect: CGRect, container: CGSize, imageSize: CGSize) -> CGRect {
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

    /// 容器内坐标点 → 归一化点（0..1，相对图片内容区；可超出 0..1 表示落在图片外）。
    private static func pointToNormalized(_ point: CGPoint, container: CGSize, imageSize: CGSize) -> CGPoint {
        let content = contentRect(container: container, image: imageSize)
        return CGPoint(
            x: (point.x - content.origin.x) / content.width,
            y: (point.y - content.origin.y) / content.height
        )
    }

    /// 归一化点 → 容器内坐标点（scaledToFit）。
    private static func normalizedToPoint(_ norm: CGPoint, container: CGSize, imageSize: CGSize) -> CGPoint {
        let content = contentRect(container: container, image: imageSize)
        return CGPoint(
            x: content.origin.x + norm.x * content.width,
            y: content.origin.y + norm.y * content.height
        )
    }
}

/// 把标注（红框 / 红箭头）烘焙进图片（用于上传附件）。
///
/// - Parameters:
///   - image: 原图。
///   - annotations: 归一化标注数组；为空时直接返回原图。
/// - Returns: 带红色标注的原图尺寸副本（绘制失败则回退原图）。
func yxb_bakeAnnotations(into image: UIImage, annotations: [ImageAnnotation]) -> UIImage {
    guard !annotations.isEmpty, let cg = image.cgImage else { return image }
    let size = image.size
    let lineWidth = max(size.width * 0.012, 4)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
        UIColor.red.setStroke()
        for ann in annotations {
            switch ann.kind {
            case .rect:
                let ns = ann.start, ne = ann.end
                let r = CGRect(
                    x: min(ns.x, ne.x) * size.width,
                    y: min(ns.y, ne.y) * size.height,
                    width: abs(ne.x - ns.x) * size.width,
                    height: abs(ne.y - ns.y) * size.height
                )
                let path = UIBezierPath(rect: r)
                path.lineWidth = lineWidth
                path.stroke()
            case .arrow:
                let s = CGPoint(x: ann.start.x * size.width, y: ann.start.y * size.height)
                let e = CGPoint(x: ann.end.x * size.width, y: ann.end.y * size.height)
                drawArrow(from: s, to: e, lineWidth: lineWidth)
            }
        }
    }
}

/// Core Graphics 绘制红色箭头（含箭头头部），坐标已为图片像素。
private func drawArrow(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) {
    let path = UIBezierPath()
    path.move(to: start)
    path.addLine(to: end)
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()

    let angle = atan2(end.y - start.y, end.x - start.x)
    let head = max(lineWidth * 4, 14)
    let a1 = angle + CGFloat(Double.pi / 7)
    let a2 = angle - CGFloat(Double.pi / 7)
    let left = CGPoint(x: end.x - head * CGFloat(cos(a1)), y: end.y - head * CGFloat(sin(a1)))
    let right = CGPoint(x: end.x - head * CGFloat(cos(a2)), y: end.y - head * CGFloat(sin(a2)))
    let headPath = UIBezierPath()
    headPath.move(to: end); headPath.addLine(to: left)
    headPath.move(to: end); headPath.addLine(to: right)
    headPath.lineWidth = lineWidth
    headPath.lineCapStyle = .round
    headPath.lineJoinStyle = .round
    headPath.stroke()
}

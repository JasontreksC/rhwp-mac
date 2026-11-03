import CoreGraphics
import CoreText
import Foundation
import ImageIO
import RhwpKit

/// 레이어 트리(PaintOp IR)를 CoreGraphics/CoreText로 그리는 렌더러.
///
/// "Rust가 배치하고 Swift가 그린다": 줄 나눔·자간·장평 폭은 엔진이 이미 계산해 `positions`에 담았다.
/// 이 렌더러는 그 위치에 글리프를 놓을 뿐 조판을 다시 계산하지 않는다.
///
/// 0단계 스파이크의 동적 딕셔너리 렌더러를 2단계의 `PageLayerTree` 모델 위로 옮긴 것이다. 같은 입력에서
/// 스파이크와 같은 픽셀을 내도록 그리기 규칙을 그대로 가져왔고, 4단계에서 엔진의 SVG 렌더러가 하던 일을 옮겨 왔다.
///
/// 파일 구성: 이 파일은 트리 순회·도형·글자 run, `DrawingObjects`는 수식·원본 SVG·각주 표식·자리 표시·양식,
/// `DrawingDecoration`은 밑줄·취소선·강조점·탭 리더, `DrawingImage`는 그림, `SVGFragmentDrawer`는 엔진이 SVG
/// 조각으로 보내는 수식·차트·WMF/EMF 그림이다.
///
/// 아직 하지 않는 것(그릴 수 없는 입력은 `RenderReport`에 `op:<이름>`·`svg:<요소>` 등으로 집계된다):
/// - 글자: 세로쓰기·회전·위/아래 첨자, 글자 겹침(`charOverlap`), 그림자·음영, 엔진이 글리프 단위로 특별 취급하는
///   가운뎃점·사각 안 숫자·옛 글꼴 글머리표
/// - 그림: 밝기·대비·그림 효과(`image:effect`), 세로쓰기 글자의 장식선
/// - SVG 조각: 무늬·마스크·필터·`clipPath`와 `url(#…)` 칠
/// - 타일링 렌더러(큰 쪽을 조각으로 나눠 그리기)는 이 렌더러가 아니라 뷰어의 배율 정책이 정한다.
public struct PageRenderer: Sendable {
    private let fontResolver: FontResolver

    public init(fontResolver: FontResolver = FontResolver()) {
        self.fontResolver = fontResolver
    }

    /// 한 쪽을 비트맵으로 그린다.
    ///
    /// - Parameter scale: px → 출력 비트맵 배율. 2면 Retina 해상도다.
    public func render(_ tree: PageLayerTree, scale: Double) throws -> RenderedPage {
        let width = tree.pageWidth * scale
        let height = tree.pageHeight * scale
        // 0 이하, NaN, 한 변이 16384px를 넘는 크기는 비트맵을 만들지 않는다(메모리 폭주 방지).
        guard width >= 1, height >= 1, width <= 16384, height <= 16384 else {
            throw RenderError.invalidPageSize(width: tree.pageWidth, height: tree.pageHeight)
        }
        let pixelWidth = Int(width.rounded(.up))
        let pixelHeight = Int(height.rounded(.up))
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RenderError.bitmapUnavailable }

        // y-down 쪽 좌표로 뒤집는다. CoreGraphics 기본은 y-up이다.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        let report = draw(tree, into: context)

        guard let image = context.makeImage() else { throw RenderError.bitmapUnavailable }
        return RenderedPage(image: image, report: report)
    }

    /// 한 쪽을 주어진 컨텍스트에 그린다.
    ///
    /// 컨텍스트는 **쪽 좌표(px, 원점 왼쪽 위, y 아래로 증가)** 로 이미 맞춰져 있어야 한다. 그림과 글자는 이
    /// 안에서 국소적으로 다시 뒤집어 그린다. 호출 전의 그래픽 상태는 보존된다.
    @discardableResult
    public func draw(_ tree: PageLayerTree, into context: CGContext) -> RenderReport {
        var drawing = Drawing(context: context, fontResolver: fontResolver)
        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)
        context.interpolationQuality = .high
        drawing.draw(tree.root)
        context.restoreGState()
        return drawing.report
    }
}

/// 한 번의 그리기 동안의 상태. 렌더마다 새로 만들어 스레드 간에 공유하지 않는다.
struct Drawing {
    let ctx: CGContext
    let fontResolver: FontResolver
    var report = RenderReport()

    init(context: CGContext, fontResolver: FontResolver) {
        ctx = context
        self.fontResolver = fontResolver
    }

    // MARK: - 트리 순회

    mutating func draw(_ node: LayerNode) {
        switch node.content {
        case let .group(_, children):
            for child in children { draw(child) }
        case let .clip(rect, _, child):
            // 표 셀·글상자·본문 영역의 잘라내기. 자식은 이 사각형 안에서만 보인다.
            ctx.saveGState()
            ctx.clip(to: rect.cgRect)
            draw(child)
            ctx.restoreGState()
        case let .leaf(ops):
            for op in ops { draw(op) }
        case let .unsupported(kind):
            report.countSkipped("node:\(kind)")
        }
    }

    mutating func draw(_ op: PaintOp) {
        switch op {
        case let .pageBackground(op): drawPageBackground(op)
        case let .textRun(op): drawTextRun(op)
        case let .line(op): drawLine(op)
        case let .rectangle(op): drawRectangle(op)
        case let .ellipse(op): drawEllipse(op)
        case let .path(op): drawPath(op)
        case let .image(op): drawImage(op)
        case let .equation(op): drawEquation(op)
        case let .rawSvg(op): drawRawSvg(op)
        case let .footnoteMarker(op): drawFootnoteMarker(op)
        case let .placeholder(op): drawPlaceholder(op)
        case let .formObject(op): drawFormObject(op)
        case let .textDecoration(op): drawTextDecoration(op)
        case let .tabLeader(op): drawTabLeader(op)
        case let .unsupported(type): report.countSkipped("op:\(type)")
        }
    }

    // MARK: - 도형

    private mutating func drawPageBackground(_ op: PageBackgroundOp) {
        if let color = op.backgroundColor {
            ctx.setFillColor(color.cgColor)
            ctx.fill(op.bbox.cgRect)
        }
        report.countRendered("op:pageBackground")
    }

    private mutating func drawLine(_ op: LineOp) {
        ctx.saveGState()
        applyShapeTransform(op.transform, about: op.bbox.cgRect)
        applyStroke(color: op.style.color, width: op.style.width, dash: op.style.dash)
        ctx.move(to: CGPoint(x: op.start.x, y: op.start.y))
        ctx.addLine(to: CGPoint(x: op.end.x, y: op.end.y))
        ctx.strokePath()
        ctx.restoreGState()
        report.countRendered("op:line")
    }

    private mutating func drawRectangle(_ op: RectangleOp) {
        let box = op.bbox.cgRect
        ctx.saveGState()
        applyShapeTransform(op.transform, about: box)
        let path = CGPath(
            roundedRect: box,
            cornerWidth: min(op.cornerRadius, box.width / 2), cornerHeight: min(op.cornerRadius, box.height / 2),
            transform: nil
        )
        fillAndStroke(path: path, style: op.style, gradient: op.gradient, bounds: box)
        ctx.restoreGState()
        report.countRendered("op:rectangle")
    }

    private mutating func drawEllipse(_ op: EllipseOp) {
        let box = op.bbox.cgRect
        ctx.saveGState()
        applyShapeTransform(op.transform, about: box)
        fillAndStroke(path: CGPath(ellipseIn: box, transform: nil), style: op.style, gradient: op.gradient, bounds: box)
        ctx.restoreGState()
        report.countRendered("op:ellipse")
    }

    private mutating func drawPath(_ op: PathOp) {
        let box = op.bbox.cgRect
        let path = CGMutablePath()
        // 타원호는 현재 점에서 시작하므로 현재 점과 부경로 시작점을 따라간다.
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        for command in op.commands {
            switch command {
            case let .moveTo(p):
                path.move(to: p.cgPoint)
                current = p.cgPoint
                subpathStart = current
            case let .lineTo(p):
                path.addLine(to: p.cgPoint)
                current = p.cgPoint
            case let .curveTo(control1, control2, end):
                path.addCurve(to: end.cgPoint, control1: control1.cgPoint, control2: control2.cgPoint)
                current = end.cgPoint
            case let .arcTo(rx, ry, rotation, largeArc, sweep, end):
                // SVG 타원호를 중심 매개변수로 바꿔 3차 베지어로 정확히 그린다(`SVGArc`).
                SVGArc.append(
                    to: path, from: current, radiusX: rx, radiusY: ry, rotationDegrees: rotation,
                    largeArc: largeArc, sweep: sweep, to: end.cgPoint
                )
                current = end.cgPoint
            case .closePath:
                path.closeSubpath()
                current = subpathStart
            case let .unsupported(type): report.countSkipped("path:\(type)")
            }
        }
        ctx.saveGState()
        applyShapeTransform(op.transform, about: box)
        // 선 전용 경로의 선 스타일은 `style`의 테두리보다 우선한다(`PathOp.lineStyle`의 약속).
        var style = op.style
        if let line = op.lineStyle {
            style.strokeColor = line.color
            style.strokeWidth = line.width
            style.strokeDash = line.dash
        }
        fillAndStroke(path: path, style: style, gradient: op.gradient, bounds: box)
        ctx.restoreGState()
        report.countRendered("op:path")
    }

    /// 채우기(단색/그라데이션) 후 테두리를 그린다.
    private mutating func fillAndStroke(path: CGPath, style: ShapeStyle, gradient: Gradient?, bounds: CGRect) {
        ctx.setAlpha(style.opacity)

        if let gradient, fillGradient(gradient, path: path, bounds: bounds) {
            // 그라데이션이 채웠다.
        } else if let fill = style.fillColor {
            ctx.addPath(path)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }

        if let stroke = style.strokeColor, style.strokeWidth > 0 {
            applyStroke(color: stroke, width: style.strokeWidth, dash: style.strokeDash)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// 그라데이션을 그린다. 원형(type 2)은 방사형으로, 줄무늬(1)·원뿔(3)·사각(4)은 엔진의 SVG 렌더러처럼 선형으로
    /// 근사한다. 그릴 수 없는 입력(색이 2개 미만 등)이면 false를 돌려 호출자가 단색 채우기로 되돌아가게 한다.
    private mutating func fillGradient(_ gradient: Gradient, path: CGPath, bounds: CGRect) -> Bool {
        guard gradient.colors.count >= 2, gradient.positions.count == gradient.colors.count,
              let cg = CGGradient(
                  colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                  colors: gradient.colors.map(\.cgColor) as CFArray,
                  locations: gradient.positions.map { CGFloat($0) }
              )
        else {
            report.countSkipped("gradient:type\(gradient.gradientType)")
            return false
        }
        if gradient.gradientType == 2 {
            // 엔진의 SVG 렌더러는 `radialGradient cx cy r=50%`를 상자 비율(objectBoundingBox)로 낸다. 중심은 상자의
            // 백분율 위치, 반지름은 가로 `width/2`·세로 `height/2`인 **타원**이다. CoreGraphics의 방사형은 원이므로
            // 중심으로 옮겨 상자 크기만큼 늘린 단위 좌표(반지름 0.5)에서 그린다. 끝 바깥은 끝 색으로 채운다(SVG pad).
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.translateBy(
                x: bounds.minX + bounds.width * CGFloat(gradient.centerX) / 100,
                y: bounds.minY + bounds.height * CGFloat(gradient.centerY) / 100
            )
            ctx.scaleBy(x: bounds.width, y: bounds.height)
            ctx.drawRadialGradient(
                cg, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 0.5,
                options: [.drawsAfterEndLocation]
            )
            ctx.restoreGState()
            return true
        }
        // 축 방향은 엔진 정본(`linear_gradient_axis`)과 같은 규칙이다. 모델의 `linearAxis`가 그 규칙을 담고 있다.
        let axis = gradient.linearAxis(in: LayerRect(
            x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height
        ))
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(cg, start: axis.start.cgPoint, end: axis.end.cgPoint, options: [])
        ctx.restoreGState()
        return true
    }

    private func applyStroke(color: LayerColor, width: Double, dash: StrokeDash) {
        ctx.setStrokeColor(color.cgColor)
        let w = CGFloat(width)
        ctx.setLineWidth(w)
        switch dash {
        case .dash: ctx.setLineDash(phase: 0, lengths: [w * 4, w * 2])
        case .dot: ctx.setLineDash(phase: 0, lengths: [w, w * 2])
        case .dashDot: ctx.setLineDash(phase: 0, lengths: [w * 4, w * 2, w, w * 2])
        case .dashDotDot: ctx.setLineDash(phase: 0, lengths: [w * 4, w * 2, w, w * 2, w, w * 2])
        case .solid: ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    /// 도형 회전/뒤집기. 회전 중심은 bbox 중심이다.
    func applyShapeTransform(_ transform: ShapeTransform, about box: CGRect) {
        guard !transform.isIdentity else { return }
        ctx.translateBy(x: box.midX, y: box.midY)
        ctx.rotate(by: CGFloat(transform.rotation * .pi / 180))
        ctx.scaleBy(x: transform.horzFlip ? -1 : 1, y: transform.vertFlip ? -1 : 1)
        ctx.translateBy(x: -box.midX, y: -box.midY)
    }

    // MARK: - 글자

    private mutating func drawTextRun(_ op: TextRunOp) {
        let text = op.text
        guard !text.isEmpty else {
            // 빈 문단 표식 등 글자가 없는 run은 그릴 것이 없다.
            report.countRendered("op:textRun(empty)")
            return
        }

        let style = op.style
        let originX = op.runToPage.e
        let baselineY = op.runToPage.f
        let color = style.color.cgColor
        let resolved = fontResolver.resolve(
            family: style.fontFamily, size: style.fontSize, bold: style.bold, italic: style.italic
        )
        if let substitute = resolved.substitute {
            report.fontSubstitutions[style.fontFamily] = substitute
        }

        ctx.saveGState()
        ctx.setFillColor(color)
        // 글자는 한 자(스칼라)씩 엔진이 계산한 위치에 놓는다. 줄 배치와 자간은 엔진의 결과를 그대로 따르고,
        // Swift는 글리프만 그린다 — 조판 결과를 두 곳에서 따로 계산하지 않기 위한 선택이다.
        let positions = op.positions
        for (index, scalar) in text.unicodeScalars.enumerated() where index < positions.count {
            let glyph = String(scalar)
            if glyph.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let line = makeLine(glyph, font: resolved.font, color: color)
            ctx.saveGState()
            ctx.translateBy(x: originX + positions[index], y: baselineY)
            // 글리프는 y-up이라 y-down 컨텍스트에서 다시 뒤집고, 장평(ratio)을 가로 배율로 적용한다.
            ctx.scaleBy(x: style.ratio, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }

        // 밑줄·취소선·강조점은 엔진이 별도 op(`textDecoration`)로 내므로 여기서 그리지 않는다.
        ctx.restoreGState()
        report.countRendered("op:textRun")
    }

    private func makeLine(_ string: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }
}

// MARK: - 모델 → CoreGraphics

extension LayerRect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

extension LayerPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

extension LayerColor {
    /// sRGB 불투명 색. 투명도는 엔진이 `opacity` 필드로 따로 싣는다.
    var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1
        )
    }
}

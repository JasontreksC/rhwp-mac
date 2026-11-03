import CoreGraphics
import CoreText
import Foundation
import RhwpKit

/// 수식·원본 SVG·각주 표식·자리 표시·양식 개체를 그린다.
///
/// 각 규칙은 엔진의 SVG 렌더러(`src/renderer/svg.rs`)를 정본으로 삼아 옮긴 것이다. 같은 규칙이 두 곳에 있으므로
/// 엔진 쪽이 바뀌면 여기도 고쳐야 한다(`mydocs/tech/macos_native_app_architecture.md` 4단계의 "중복 위험").
extension Drawing {
    // MARK: - 수식·원본 SVG

    /// 수식은 엔진이 배치를 끝낸 SVG 조각이다. bbox 왼쪽 위에 놓되 저장된 수식 상자와 엔진 계산 크기가 다르면
    /// `EquationOp.contentScale`(엔진 SVG 렌더러와 같은 규칙)로 늘이거나 줄인다.
    mutating func drawEquation(_ op: EquationOp) {
        ctx.saveGState()
        ctx.translateBy(x: op.bbox.x, y: op.bbox.y)
        let scale = op.contentScale
        // 엔진도 1% 이내의 차이는 배율을 적용하지 않는다. 같은 기준을 써야 같은 위치에 놓인다.
        if abs(scale.x - 1) > 0.01 || abs(scale.y - 1) > 0.01 {
            ctx.scaleBy(x: scale.x, y: scale.y)
        }
        report.merge(SVGFragmentDrawer.draw(op.svgContent, in: ctx, fontResolver: fontResolver))
        ctx.restoreGState()
        report.countRendered("op:equation")
    }

    /// 원본 SVG 조각(OOXML·OLE 차트). 좌표는 이미 쪽 좌표라서 변환 없이 그린다.
    mutating func drawRawSvg(_ op: RawSvgOp) {
        report.merge(SVGFragmentDrawer.draw(op.svg, in: ctx, fontResolver: fontResolver))
        report.countRendered("op:rawSvg")
    }

    // MARK: - 각주 표식

    /// 본문의 위 첨자 번호. 글자 크기는 엔진이 이미 줄여 보냈고 기준선은 bbox 높이의 40% 지점이다
    /// (엔진 SVG 렌더러의 `FootnoteMarker` 규칙).
    mutating func drawFootnoteMarker(_ op: FootnoteMarkerOp) {
        drawString(
            op.text, x: op.bbox.x, baseline: op.bbox.y + op.bbox.height * 0.4,
            family: op.fontFamily.isEmpty ? "sans-serif" : op.fontFamily, size: op.fontSize,
            bold: false, italic: false, color: op.color
        )
        report.countRendered("op:footnoteMarker")
    }

    // MARK: - 자리 표시

    /// OLE 개체는 점선 상자와 가운데 라벨로 그린다. 그림 미지정(`missingPicture`)은 한컴의 **인쇄 출력에는 나오지
    /// 않고 편집 화면에만** 보이므로 그리지 않는다. 충실도 기준이 한컴 PDF(인쇄 출력)이고 엔진의 SVG 렌더러도
    /// 기본값에서 같은 선택을 한다.
    mutating func drawPlaceholder(_ op: PlaceholderOp) {
        guard op.kind == .ole else {
            report.countRendered("op:placeholder(missingPicture,hidden)")
            return
        }
        let box = op.bbox.cgRect
        ctx.saveGState()
        ctx.setFillColor(op.fillColor.cgColor)
        ctx.fill(box)
        ctx.setStrokeColor(op.strokeColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [6, 3])
        ctx.stroke(box)
        ctx.restoreGState()

        let fontSize = min(max(min(box.width, box.height) * 0.06, 12), 28)
        drawString(
            op.label, x: box.midX, baseline: box.midY, family: "sans-serif", size: fontSize,
            bold: false, italic: false, color: op.strokeColor, anchor: .middle, centerVertically: true
        )
        report.countRendered("op:placeholder")
    }

    // MARK: - 양식 개체

    /// 양식 개체는 엔진이 모양을 도형 조각으로 풀어 보낸다(`form_appearance`). 닫힌 폴리라인은 면으로,
    /// 열린 폴리라인은 선으로 그린다는 점까지 엔진 SVG 렌더러와 같다.
    mutating func drawFormObject(_ op: FormObjectOp) {
        for primitive in op.primitives {
            switch primitive {
            case let .rect(box, color):
                ctx.setFillColor(color.cgColor)
                ctx.fill(box.cgRect)
            case let .circle(x, y, radius, color):
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
            case let .polyline(points, color, width, closed):
                guard let first = points.first else { continue }
                let path = CGMutablePath()
                path.move(to: first.cgPoint)
                for point in points.dropFirst() { path.addLine(to: point.cgPoint) }
                if closed {
                    path.closeSubpath()
                    ctx.addPath(path)
                    ctx.setFillColor(color.cgColor)
                    ctx.fillPath()
                } else {
                    ctx.saveGState()
                    ctx.addPath(path)
                    ctx.setStrokeColor(color.cgColor)
                    ctx.setLineWidth(width)
                    ctx.setLineDash(phase: 0, lengths: [])
                    ctx.strokePath()
                    ctx.restoreGState()
                }
            case let .unsupported(kind):
                report.countSkipped("form:\(kind)")
            }
        }
        if let label = op.label {
            drawString(
                label.text, x: label.x, baseline: label.baseline, family: label.fontFamily, size: label.fontSize,
                bold: label.bold, italic: label.italic, color: label.color
            )
        }
        report.countRendered("op:formObject")
    }

    // MARK: - 글자 한 줄

    enum TextAnchor { case start, middle }

    /// 문자열을 한 줄로 그린다. `x`·`baseline`은 쪽 좌표다. 엔진이 글자별 위치를 주지 않는 짧은 글자(표식, 라벨)용이다.
    mutating func drawString(
        _ text: String, x: Double, baseline: Double, family: String, size: Double, bold: Bool, italic: Bool,
        color: LayerColor, anchor: TextAnchor = .start, centerVertically: Bool = false
    ) {
        guard !text.isEmpty, size > 0 else { return }
        let resolved = fontResolver.resolve(family: family, size: size, bold: bold, italic: italic)
        if let substitute = resolved.substitute { report.fontSubstitutions[resolved.requested] = substitute }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): resolved.font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var originX = x
        if anchor == .middle { originX -= CTLineGetTypographicBounds(line, nil, nil, nil) / 2 }
        var originY = baseline
        if centerVertically {
            // SVG `dominant-baseline: central`: 글줄의 가운데를 baseline 위치에 맞춘다.
            originY += (CTFontGetAscent(resolved.font) - CTFontGetDescent(resolved.font)) / 2
        }
        ctx.saveGState()
        ctx.translateBy(x: originX, y: originY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

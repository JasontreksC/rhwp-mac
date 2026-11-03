import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// 엔진이 만든 SVG **조각**(수식, OOXML·OLE 차트, WMF·EMF를 바꾼 SVG 그림)을 CoreGraphics로 그린다.
///
/// 범용 SVG 렌더러가 아니다. 엔진이 실제로 내보내는 부분집합만 다룬다.
/// - 도형: `rect`(`rx`·`ry`), `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path`(M L H V C S Q T A Z, 상대 좌표 포함)
/// - 글자: `text`와 `tspan`(`x`·`y`·`dx`·`dy`·`font-*`·`text-anchor`·`dominant-baseline`), `image`(data URI, 래스터·SVG)
/// - 묶음: `g`·중첩 `svg`(`transform`: translate·scale·rotate·matrix, 중첩 `svg`는 `x`·`y`·`width`·`height`)
/// - 칠: `fill`·`stroke`·`*-width`·`*-opacity`·`stroke-dasharray`·`stroke-linecap`·`stroke-linejoin`·`fill-rule`, `style="…"`
///
/// 그 밖의 요소(`defs`·무늬·마스크·필터·`clipPath`)와 `url(#…)` 칠은 그리지 않고 `svg:<이름>`으로 집계한다. 이
/// 목록은 엔진 쪽 규칙과의 **중복**이므로 엔진이 새 SVG 요소를 내보내기 시작하면 여기도 같이 고쳐야 한다.
///
/// 먼저 XML을 가벼운 트리(`SVGNode`)로 읽고 나서 그린다. 읽으면서 바로 그리지 않는 까닭은 그림 안의 SVG 그림을
/// 그릴 때 파서가 다시 불리기 때문이다(`NSXMLParser`는 재진입을 지원하지 않고 예외로 죽는다). 그릴 때 컨텍스트는
/// 조각의 원점이 (0, 0)이고 y가 아래로 증가하는 쪽 좌표계로 이미 맞춰져 있어야 한다.
final class SVGFragmentDrawer {
    private struct Style {
        var fill: CGColor? = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        var stroke: CGColor?
        var strokeWidth: CGFloat = 1
        var dash: [CGFloat] = []
        var lineCap: CGLineCap = .butt
        var lineJoin: CGLineJoin = .miter
        var evenOdd = false
        var opacity: CGFloat = 1
        var fillOpacity: CGFloat = 1
        var strokeOpacity: CGFloat = 1
        var fontFamily = "serif"
        var fontSize: CGFloat = 16
        var bold = false
        var italic = false
        var anchor = Anchor.start
        var baseline = Baseline.alphabetic
    }

    private enum Anchor { case start, middle, end }
    private enum Baseline { case alphabetic, central }

    /// `text` 안의 글자 한 조각. `tspan`마다 하나이고, 그 밖의 직접 글자도 한 조각이다.
    private struct TextSegment {
        var content: String
        var style: Style
        var dx: CGFloat
        var dy: CGFloat
        /// 절대 위치 지정(`tspan x`·`y`). 없으면 앞 조각이 끝난 곳에서 이어진다.
        var x: CGFloat?
        var y: CGFloat?
    }

    private let ctx: CGContext
    private let fontResolver: FontResolver
    private(set) var report = RenderReport()

    /// 그림 안의 SVG 그림이 또 SVG 그림을 품는 깊이. 악의적인 순환 문서가 무한히 파고들지 못하게 막는다.
    private let depth: Int
    private static let maxImageDepth = 3

    private init(context: CGContext, fontResolver: FontResolver, depth: Int) {
        ctx = context
        self.fontResolver = fontResolver
        self.depth = depth
    }

    /// `fragment`를 현재 컨텍스트 원점에 그리고, 건너뛴 요소 집계를 돌려준다.
    static func draw(_ fragment: String, in context: CGContext, fontResolver: FontResolver) -> RenderReport {
        draw(fragment, in: context, fontResolver: fontResolver, depth: 0)
    }

    private static func draw(
        _ fragment: String, in context: CGContext, fontResolver: FontResolver, depth: Int
    ) -> RenderReport {
        let drawer = SVGFragmentDrawer(context: context, fontResolver: fontResolver, depth: depth)
        // 조각은 루트가 여럿일 수 있어 XML로 읽으려면 감싸야 한다. `xlink` 접두사를 선언해 두어야 파서가
        // 이름공간 오류로 멈추지 않는다.
        let wrapped = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">"
            + fragment + "</svg>"
        let parsed = SVGNode.parse(Data(wrapped.utf8))
        if !parsed.complete { drawer.report.countSkipped("svg:parseError") }
        // 중간에 멈춘 문서도 거기까지 읽은 트리는 그린다.
        context.saveGState()
        drawer.drawChildren(of: parsed.root, inherited: Style())
        context.restoreGState()
        return drawer.report
    }

    // MARK: - 트리 순회

    private func drawChildren(of node: SVGNode, inherited: Style) {
        for case let .element(child) in node.children { drawElement(child, inherited: inherited) }
    }

    private func drawElement(_ node: SVGNode, inherited: Style) {
        let name = node.name
        // 정의부는 안쪽을 그리지 않는다. 그림에 영향을 줄 수 있는 것만 집계한다.
        if Self.definitionElements.contains(name) {
            if Self.countedDefinitionElements.contains(name) { report.countSkipped("svg:\(name)") }
            return
        }

        var attributes = node.attributes
        if let inline = attributes["style"] { Self.mergeInlineStyle(inline, into: &attributes) }
        var style = inherited
        apply(attributes, to: &style)

        ctx.saveGState()
        defer { ctx.restoreGState() }
        if let transform = attributes["transform"], let matrix = Self.parseTransform(transform) {
            ctx.concatenate(matrix)
        }

        switch name {
        case "g":
            drawChildren(of: node, inherited: style)
        case "svg":
            // 중첩 svg: 위치로 옮기고, 크기가 있으면 그 안으로 자른다(`overflow: visible`이면 자르지 않는다).
            ctx.translateBy(x: number(attributes["x"]), y: number(attributes["y"]))
            if let w = optionalNumber(attributes["width"]), let h = optionalNumber(attributes["height"]),
               attributes["overflow"] != "visible" {
                ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: h))
            }
            drawChildren(of: node, inherited: style)
        case "rect": drawRect(attributes, style)
        case "circle":
            let r = number(attributes["r"])
            let box = CGRect(x: number(attributes["cx"]) - r, y: number(attributes["cy"]) - r, width: 2 * r, height: 2 * r)
            paint(CGPath(ellipseIn: box, transform: nil), style)
            report.countRendered("svg:circle")
        case "ellipse":
            let rx = number(attributes["rx"]), ry = number(attributes["ry"])
            let box = CGRect(x: number(attributes["cx"]) - rx, y: number(attributes["cy"]) - ry, width: 2 * rx, height: 2 * ry)
            paint(CGPath(ellipseIn: box, transform: nil), style)
            report.countRendered("svg:ellipse")
        case "line":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: number(attributes["x1"]), y: number(attributes["y1"])))
            path.addLine(to: CGPoint(x: number(attributes["x2"]), y: number(attributes["y2"])))
            // 선은 칠할 면이 없으므로 stroke만 쓴다.
            var lineStyle = style
            lineStyle.fill = nil
            paint(path, lineStyle)
            report.countRendered("svg:line")
        case "polyline", "polygon":
            let values = Self.numbers(in: attributes["points"] ?? "")
            let path = CGMutablePath()
            var index = 0
            while index + 1 < values.count {
                let point = CGPoint(x: values[index], y: values[index + 1])
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                index += 2
            }
            if name == "polygon" { path.closeSubpath() }
            paint(path, style)
            report.countRendered("svg:\(name)")
        case "path":
            if let d = attributes["d"] {
                paint(Self.parsePath(d), style)
                report.countRendered("svg:path")
            }
        case "text":
            var segments: [TextSegment] = []
            let hasSpans = collectSegments(of: node, style: style, into: &segments)
            drawText(
                x: number(attributes["x"]), y: number(attributes["y"]), style: style, segments: segments, hasSpans: hasSpans
            )
        case "image":
            drawImage(attributes)
        default:
            // 모르는 요소는 집계하되 자식은 묶음으로 그린다(래퍼 요소가 내용을 감싸는 경우가 많다).
            report.countSkipped("svg:\(name)")
            drawChildren(of: node, inherited: style)
        }
    }

    /// `text`의 직접 글자와 `tspan`을 순서대로 조각으로 모은다. `tspan`이 하나라도 있었는지를 돌려준다.
    @discardableResult
    private func collectSegments(of node: SVGNode, style: Style, into segments: inout [TextSegment]) -> Bool {
        var hasSpans = false
        for child in node.children {
            switch child {
            case let .text(string):
                segments.append(TextSegment(content: string, style: style, dx: 0, dy: 0, x: nil, y: nil))
            case let .element(element) where element.name == "tspan":
                hasSpans = true
                var spanAttributes = element.attributes
                if let inline = spanAttributes["style"] { Self.mergeInlineStyle(inline, into: &spanAttributes) }
                var spanStyle = style
                apply(spanAttributes, to: &spanStyle)
                // `tspan` 안의 직접 글자가 이 조각이다. 위치(dx·dy·x·y)는 조각의 첫 글자에만 적용한다.
                var inner: [TextSegment] = []
                collectSegments(of: element, style: spanStyle, into: &inner)
                if var first = inner.first {
                    first.dx = number(spanAttributes["dx"])
                    first.dy = number(spanAttributes["dy"])
                    first.x = optionalNumber(spanAttributes["x"])
                    first.y = optionalNumber(spanAttributes["y"])
                    inner[0] = first
                } else if spanAttributes["dx"] != nil || spanAttributes["x"] != nil {
                    // 글자 없는 `tspan`도 위치 이동은 이어지는 조각에 영향을 주지만 근사에서 생략한다.
                    report.countSkipped("svg:tspan(empty positioned)")
                }
                segments.append(contentsOf: inner)
            case let .element(element):
                report.countSkipped("svg:\(element.name)(in text)")
            }
        }
        return hasSpans
    }

    // MARK: - 속성

    /// 안에 자식이 있어도 그리지 않는 정의부. 집계 대상은 그림에 영향을 줄 수 있는 것만이다.
    private static let definitionElements: Set<String> = [
        "defs", "clipPath", "mask", "pattern", "marker", "symbol", "linearGradient", "radialGradient",
        "style", "title", "desc", "metadata", "filter",
    ]
    private static let countedDefinitionElements: Set<String> = [
        "clipPath", "mask", "pattern", "marker", "linearGradient", "radialGradient", "filter",
    ]

    private func number(_ text: String?) -> CGFloat { optionalNumber(text) ?? 0 }

    /// `12`, `12px`, `-1.5e2`를 읽는다. 백분율은 기준 크기를 모르므로 nil이다.
    private func optionalNumber(_ text: String?) -> CGFloat? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty, !text.hasSuffix("%") else { return nil }
        if text.hasSuffix("px") { text.removeLast(2) }
        return Double(text).map { CGFloat($0) }
    }

    private func apply(_ attributes: [String: String], to style: inout Style) {
        if let fill = attributes["fill"] {
            style.fill = Self.parseColor(fill, orElse: style.fill)
            // 무늬·그라데이션 칠(`url(#…)`)은 그리지 못한다. 단색으로 잘못 칠하느니 칠하지 않는다.
            if fill.hasPrefix("url(") {
                style.fill = nil
                report.countSkipped("svg:paint(url)")
            }
        }
        if let stroke = attributes["stroke"] {
            style.stroke = Self.parseColor(stroke, orElse: style.stroke)
            if stroke.hasPrefix("url(") {
                style.stroke = nil
                report.countSkipped("svg:paint(url)")
            }
        }
        if let width = optionalNumber(attributes["stroke-width"]) { style.strokeWidth = width }
        if let dash = attributes["stroke-dasharray"] {
            style.dash = dash == "none" ? [] : Self.numbers(in: dash).map { CGFloat($0) }
            // 홀수 개면 SVG 규격대로 한 번 더 이어 붙여 짝수로 만든다.
            if style.dash.count % 2 == 1 { style.dash += style.dash }
        }
        switch attributes["stroke-linecap"] {
        case "round": style.lineCap = .round
        case "square": style.lineCap = .square
        case "butt": style.lineCap = .butt
        default: break
        }
        switch attributes["stroke-linejoin"] {
        case "round": style.lineJoin = .round
        case "bevel": style.lineJoin = .bevel
        case "miter": style.lineJoin = .miter
        default: break
        }
        if let rule = attributes["fill-rule"] { style.evenOdd = rule == "evenodd" }
        if let value = optionalNumber(attributes["opacity"]) { style.opacity = value }
        if let value = optionalNumber(attributes["fill-opacity"]) { style.fillOpacity = value }
        if let value = optionalNumber(attributes["stroke-opacity"]) { style.strokeOpacity = value }
        if let family = attributes["font-family"] { style.fontFamily = family }
        if let size = optionalNumber(attributes["font-size"]) { style.fontSize = size }
        if let weight = attributes["font-weight"] {
            style.bold = weight == "bold" || weight == "bolder" || (Int(weight) ?? 400) >= 600
        }
        if let fontStyle = attributes["font-style"] { style.italic = fontStyle == "italic" || fontStyle == "oblique" }
        switch attributes["text-anchor"] {
        case "middle": style.anchor = .middle
        case "end": style.anchor = .end
        case "start": style.anchor = .start
        default: break
        }
        switch attributes["dominant-baseline"] {
        case "central", "middle": style.baseline = .central
        case "alphabetic", "auto": style.baseline = .alphabetic
        default: break
        }
    }

    /// `style="fill:red;stroke:#000"`를 개별 속성으로 풀어 같은 이름의 속성보다 앞세운다(CSS 우선순위).
    private static func mergeInlineStyle(_ inline: String, into attributes: inout [String: String]) {
        for declaration in inline.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            attributes[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - 색

    /// 알 수 없는 값(그라데이션 참조 등)은 기존 색을 유지한다. `none`·`transparent`는 칠하지 않는다는 뜻의 nil이다.
    private static func parseColor(_ text: String, orElse current: CGColor?) -> CGColor? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "none", "transparent": return nil
        case "currentcolor", "inherit": return current
        default: break
        }
        if value.hasPrefix("#") {
            let hex = String(value.dropFirst())
            let expanded = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
            guard expanded.count == 6, let number = UInt32(expanded, radix: 16) else { return current }
            return CGColor(
                srgbRed: CGFloat((number >> 16) & 0xFF) / 255, green: CGFloat((number >> 8) & 0xFF) / 255,
                blue: CGFloat(number & 0xFF) / 255, alpha: 1
            )
        }
        if value.hasPrefix("rgb") {
            let components = numbers(in: value)
            guard components.count >= 3 else { return current }
            let alpha = components.count >= 4 ? components[3] : 1
            return CGColor(
                srgbRed: components[0] / 255, green: components[1] / 255, blue: components[2] / 255, alpha: alpha
            )
        }
        if let named = namedColors[value] { return named }
        return current
    }

    private static let namedColors: [String: CGColor] = {
        func gray(_ v: CGFloat) -> CGColor { CGColor(srgbRed: v, green: v, blue: v, alpha: 1) }
        return [
            "black": gray(0), "white": gray(1), "gray": gray(0.5), "grey": gray(0.5), "silver": gray(0.75),
            "red": CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            "green": CGColor(srgbRed: 0, green: 0.5, blue: 0, alpha: 1),
            "blue": CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
        ]
    }()

    // MARK: - 그리기

    private func withAlpha(_ color: CGColor, _ alpha: CGFloat) -> CGColor {
        alpha >= 1 ? color : (color.copy(alpha: color.alpha * alpha) ?? color)
    }

    private func paint(_ path: CGPath, _ style: Style) {
        if let fill = style.fill {
            ctx.addPath(path)
            ctx.setFillColor(withAlpha(fill, style.fillOpacity * style.opacity))
            ctx.fillPath(using: style.evenOdd ? .evenOdd : .winding)
        }
        if let stroke = style.stroke, style.strokeWidth > 0 {
            ctx.addPath(path)
            ctx.setStrokeColor(withAlpha(stroke, style.strokeOpacity * style.opacity))
            ctx.setLineWidth(style.strokeWidth)
            ctx.setLineCap(style.lineCap)
            ctx.setLineJoin(style.lineJoin)
            ctx.setLineDash(phase: 0, lengths: style.dash)
            ctx.strokePath()
        }
    }

    private func drawRect(_ attributes: [String: String], _ style: Style) {
        let box = CGRect(
            x: number(attributes["x"]), y: number(attributes["y"]),
            width: number(attributes["width"]), height: number(attributes["height"])
        )
        guard box.width > 0, box.height > 0 else { return }
        // rx·ry는 하나만 있으면 다른 쪽도 같다(SVG 규격). 반지름은 반 변을 넘지 못한다.
        let rx = optionalNumber(attributes["rx"]), ry = optionalNumber(attributes["ry"])
        let cornerX = min(rx ?? ry ?? 0, box.width / 2), cornerY = min(ry ?? rx ?? 0, box.height / 2)
        let path = cornerX > 0 || cornerY > 0
            ? CGPath(roundedRect: box, cornerWidth: cornerX, cornerHeight: cornerY, transform: nil)
            : CGPath(rect: box, transform: nil)
        paint(path, style)
        report.countRendered("svg:rect")
    }

    private func drawText(x: CGFloat, y: CGFloat, style: Style, segments initial: [TextSegment], hasSpans: Bool) {
        // 조각을 앞에서부터 이어 그린다. `tspan`이 없으면 SVG 기본 규칙대로 앞뒤 공백을 접고, 있으면 조각 사이의
        // 공백이 글자 간격이므로 줄바꿈만 공백으로 바꾼다.
        var segments = initial
        if !hasSpans {
            for index in segments.indices {
                segments[index].content = segments[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            for index in segments.indices {
                segments[index].content = segments[index].content
                    .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
            }
            // 조각 사이의 서식용 줄바꿈 공백(공백만인 조각이 문서 서식에서 온 경우)은 의미가 없다. 공백만 있는 조각은
            // 위치 이동(`dx`)과 함께 올 때만 남긴다.
            segments.removeAll { $0.content.trimmingCharacters(in: .whitespaces).isEmpty && $0.dx == 0 && $0.x == nil }
        }
        segments.removeAll { $0.content.isEmpty }
        guard !segments.isEmpty else { return }

        struct Laid {
            var line: CTLine
            var font: CTFont
            var width: CGFloat
            var segment: TextSegment
        }
        var laid: [Laid] = []
        for segment in segments {
            guard let color = segment.style.fill else { continue }
            let resolved = fontResolver.resolve(
                familyList: segment.style.fontFamily, size: Double(segment.style.fontSize),
                bold: segment.style.bold, italic: segment.style.italic
            )
            if let substitute = resolved.substitute { report.fontSubstitutions[resolved.requested] = substitute }
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): resolved.font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    withAlpha(color, segment.style.fillOpacity * segment.style.opacity),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: segment.content, attributes: attributes))
            laid.append(Laid(
                line: line, font: resolved.font, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)),
                segment: segment
            ))
        }
        guard !laid.isEmpty else { return }

        // text-anchor는 글줄 전체 폭에 대해 적용한다(절대 위치로 끊긴 조각은 첫 덩어리 기준으로 근사한다).
        var penX = x
        var penY = y
        switch style.anchor {
        case .start: break
        case .middle: penX -= laid.reduce(0) { $0 + $1.width } / 2
        case .end: penX -= laid.reduce(0) { $0 + $1.width }
        }
        for item in laid {
            if let x = item.segment.x { penX = x }
            if let y = item.segment.y { penY = y }
            penX += item.segment.dx
            penY += item.segment.dy
            var baselineY = penY
            if item.segment.style.baseline == .central {
                // 글줄의 가운데(ascent와 descent의 중점)를 y에 맞춘다.
                baselineY += (CTFontGetAscent(item.font) - CTFontGetDescent(item.font)) / 2
            }
            ctx.saveGState()
            ctx.translateBy(x: penX, y: baselineY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(item.line, ctx)
            ctx.restoreGState()
            penX += item.width
        }
        report.countRendered("svg:text")
    }

    private func drawImage(_ attributes: [String: String]) {
        let href = attributes["href"] ?? attributes["xlink:href"] ?? ""
        guard href.hasPrefix("data:"), let comma = href.firstIndex(of: ","), href[..<comma].hasSuffix(";base64"),
              let data = Data(base64Encoded: String(href[href.index(after: comma)...]), options: .ignoreUnknownCharacters)
        else {
            report.countSkipped("svg:image(undecodable)")
            return
        }
        let box = CGRect(
            x: number(attributes["x"]), y: number(attributes["y"]),
            width: number(attributes["width"]), height: number(attributes["height"])
        )
        guard box.width > 0, box.height > 0 else { return }
        let mediaType = href[href.index(href.startIndex, offsetBy: 5) ..< comma].split(separator: ";").first ?? ""
        let stretch = attributes["preserveAspectRatio"]?.hasPrefix("none") ?? false

        if mediaType == "image/svg+xml" {
            guard depth < Self.maxImageDepth, let svg = String(data: data, encoding: .utf8) else {
                report.countSkipped("svg:image(svg too deep)")
                return
            }
            report.merge(Self.drawSVGImage(
                svg, in: box, preserveAspect: !stretch, context: ctx, fontResolver: fontResolver, depth: depth + 1
            ))
            report.countRendered("svg:image(svg)")
            return
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            report.countSkipped("svg:image(undecodable)")
            return
        }
        // `preserveAspectRatio` 기본값은 `xMidYMid meet`: 비율을 지키며 상자 안에 가운데로 맞춘다.
        let target = stretch ? box : Self.fit(
            CGSize(width: image.width, height: image.height), in: box
        )
        ctx.saveGState()
        ctx.translateBy(x: target.minX, y: target.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        ctx.restoreGState()
        report.countRendered("svg:image")
    }

    /// 크기 `size`의 내용을 `box` 안에 비율을 지키며 가운데로 맞춘 사각형(`xMidYMid meet`).
    private static func fit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }

    /// SVG **그림**(`<svg viewBox=…>` 문서 전체)을 `box` 안에 그린다. WMF·EMF를 엔진이 SVG로 바꾼 그림과
    /// 래스터를 감싼 SVG가 이 경로로 온다.
    ///
    /// `viewBox`(없으면 `width`·`height`)를 `box`에 `xMidYMid meet`로 맞추고 상자 밖은 자른다. 안쪽 `svg` 루트는
    /// 변환 없는 묶음으로 취급한다(위치·배율은 여기서 한 번만 정한다).
    static func drawSVGImage(
        _ svg: String, in box: CGRect, preserveAspect: Bool = true, context: CGContext, fontResolver: FontResolver,
        depth: Int = 0
    ) -> RenderReport {
        let root = rootAttributes(of: svg)
        var view: [Double] = []
        if let viewBox = root["viewBox"] { view = numbers(in: viewBox) }
        if view.count != 4, let w = Double(root["width"] ?? ""), let h = Double(root["height"] ?? "") { view = [0, 0, w, h] }
        context.saveGState()
        context.clip(to: box)
        if view.count == 4, view[2] > 0, view[3] > 0 {
            let target = preserveAspect ? fit(CGSize(width: view[2], height: view[3]), in: box) : box
            context.translateBy(x: target.minX, y: target.minY)
            context.scaleBy(x: target.width / view[2], y: target.height / view[3])
            context.translateBy(x: -view[0], y: -view[1])
        } else {
            context.translateBy(x: box.minX, y: box.minY)
        }
        let report = draw(svg, in: context, fontResolver: fontResolver, depth: depth)
        context.restoreGState()
        return report
    }

    /// 문서 첫 `<svg …>` 태그의 속성. 본문을 XML로 읽기 전에 `viewBox`만 필요할 때 쓴다.
    private static func rootAttributes(of svg: String) -> [String: String] {
        guard let start = svg.range(of: "<svg"), let end = svg[start.upperBound...].firstIndex(of: ">") else { return [:] }
        let tag = String(svg[start.upperBound ..< end])
        var result: [String: String] = [:]
        // name="value" 또는 name='value'.
        let pattern = try? NSRegularExpression(pattern: "([A-Za-z:_-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")
        let ns = tag as NSString
        pattern?.enumerateMatches(in: tag, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let value = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2))
                : ns.substring(with: match.range(at: 3))
            result[ns.substring(with: match.range(at: 1))] = value
        }
        return result
    }

    // MARK: - 변환

    /// `translate(…) scale(…) rotate(…) matrix(…)` 목록을 왼쪽부터 차례로 곱한다. 알 수 없는 함수가 있으면 nil이다.
    static func parseTransform(_ text: String) -> CGAffineTransform? {
        var result = CGAffineTransform.identity
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")"), open < close {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\n\t"))
            let values = numbers(in: String(rest[rest.index(after: open) ..< close])).map { CGFloat($0) }
            rest = rest[rest.index(after: close)...]
            let step: CGAffineTransform
            switch (name, values.count) {
            case ("translate", 1): step = CGAffineTransform(translationX: values[0], y: 0)
            case ("translate", 2): step = CGAffineTransform(translationX: values[0], y: values[1])
            case ("scale", 1): step = CGAffineTransform(scaleX: values[0], y: values[0])
            case ("scale", 2): step = CGAffineTransform(scaleX: values[0], y: values[1])
            case ("rotate", 1): step = CGAffineTransform(rotationAngle: values[0] * .pi / 180)
            case ("rotate", 3):
                step = CGAffineTransform(translationX: values[1], y: values[2])
                    .rotated(by: values[0] * .pi / 180)
                    .translatedBy(x: -values[1], y: -values[2])
            case ("matrix", 6):
                step = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            default: return nil
            }
            // SVG 변환 목록 `A B`는 점에 B를 먼저 적용한다. CoreGraphics의 `x.concatenating(y)`는 x를 먼저
            // 적용하므로 새 단계를 안쪽(먼저 적용)에 둔다.
            result = step.concatenating(result)
        }
        return result
    }

    // MARK: - 숫자·경로

    /// 쉼표·공백으로 갈라진 수 목록을 읽는다(`1.5.5`는 1.5와 .5, `1-2`는 1과 -2로 읽는다).
    static func numbers(in text: String) -> [Double] {
        var scanner = PathScanner(text)
        var values: [Double] = []
        while let value = scanner.number() { values.append(value) }
        return values
    }

    /// SVG `d` 속성을 경로로 바꾼다. 문법이 틀리면 거기까지 읽은 경로를 돌려준다(SVG 오류 처리 규칙).
    static func parsePath(_ d: String) -> CGPath {
        var scanner = PathScanner(d)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        // 이전 곡선의 마지막 제어점(S·T의 반사용).
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character?

        while true {
            scanner.skipSeparators()
            if let next = scanner.peekCommand() {
                command = next
                scanner.advance()
            } else if scanner.atEnd {
                break
            } else if command == nil {
                break
            }
            guard let cmd = command else { break }
            let relative = cmd.isLowercase
            let base = relative ? current : .zero

            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return CGPoint(x: base.x + x, y: base.y + y)
            }

            switch cmd.uppercased() {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
                // 이어지는 좌표쌍은 암묵적 lineto다.
                command = relative ? "l" : "L"
                lastCubicControl = nil
                lastQuadControl = nil
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastCubicControl = nil
                lastQuadControl = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let end = point() else { return path }
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil
                current = end
            case "S":
                guard let c2 = point(), let end = point() else { return path }
                let c1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil
                current = end
            case "Q":
                guard let control = point(), let end = point() else { return path }
                path.addQuadCurve(to: end, control: control)
                lastQuadControl = control
                lastCubicControl = nil
                current = end
            case "T":
                guard let end = point() else { return path }
                let control = lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addQuadCurve(to: end, control: control)
                lastQuadControl = control
                lastCubicControl = nil
                current = end
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let end = point()
                else { return path }
                SVGArc.append(
                    to: path, from: current, radiusX: rx, radiusY: ry, rotationDegrees: rotation,
                    largeArc: large, sweep: sweep, to: end
                )
                current = end
                lastCubicControl = nil
                lastQuadControl = nil
            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil
                lastQuadControl = nil
                // Z 뒤에는 좌표가 오지 않으므로 다음 명령 글자를 기다린다.
                command = nil
            default:
                return path
            }
        }
        return path
    }
}

/// SVG 경로·수 목록용 작은 스캐너.
private struct PathScanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ text: String) { scalars = Array(text.unicodeScalars) }

    var atEnd: Bool { index >= scalars.count }

    mutating func advance() { index += 1 }

    mutating func skipSeparators() {
        while index < scalars.count, scalars[index] == " " || scalars[index] == "," || scalars[index] == "\n"
            || scalars[index] == "\t" || scalars[index] == "\r" {
            index += 1
        }
    }

    /// 다음 글자가 경로 명령이면 돌려준다(소비하지 않는다). `e`·`E`는 지수라 명령이 아니다.
    func peekCommand() -> Character? {
        guard index < scalars.count else { return nil }
        let scalar = scalars[index]
        guard scalar.properties.isAlphabetic, scalar != "e", scalar != "E" else { return nil }
        return Character(scalar)
    }

    /// 호의 플래그는 `0`/`1` 한 글자이고 뒤에 구분자가 없을 수 있다(`a1 1 0 012 3`).
    mutating func flag() -> Bool? {
        skipSeparators()
        guard index < scalars.count, scalars[index] == "0" || scalars[index] == "1" else { return nil }
        defer { index += 1 }
        return scalars[index] == "1"
    }

    mutating func number() -> Double? {
        skipSeparators()
        let start = index
        var sawDigit = false
        var sawDot = false
        if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" { index += 1 }
        while index < scalars.count {
            let scalar = scalars[index]
            if ("0" ... "9").contains(scalar) {
                sawDigit = true
                index += 1
            } else if scalar == ".", !sawDot {
                sawDot = true
                index += 1
            } else {
                break
            }
        }
        guard sawDigit else {
            index = start
            return nil
        }
        // 지수부: e다음에 부호와 숫자가 올 때만 수의 일부다.
        if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
            var probe = index + 1
            if probe < scalars.count, scalars[probe] == "+" || scalars[probe] == "-" { probe += 1 }
            if probe < scalars.count, ("0" ... "9").contains(scalars[probe]) {
                while probe < scalars.count, ("0" ... "9").contains(scalars[probe]) { probe += 1 }
                index = probe
            }
        }
        var text = ""
        text.unicodeScalars.append(contentsOf: scalars[start ..< index])
        return Double(text)
    }
}

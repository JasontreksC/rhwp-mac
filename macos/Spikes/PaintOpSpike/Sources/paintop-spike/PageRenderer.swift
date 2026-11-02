import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 레이어 트리(PaintOp IR)를 CoreGraphics/CoreText로 재생하는 스파이크 렌더러.
///
/// 목적은 "Rust가 만든 IR만으로 Swift가 한 쪽을 그릴 수 있는가"의 판단이다.
/// 그래서 JSON은 `JSONSerialization`의 동적 딕셔너리로 읽고(스키마 모델링은 2단계의 몫),
/// 지원하지 않는 op는 건너뛰되 종류별로 집계해 커버리지를 보고한다.
///
/// 좌표계: 레이어 트리는 `page-top-left-y-down`(px)이다. 컨텍스트를 y-down으로 뒤집어
/// 그대로 쓰고, 글자와 이미지만 국소적으로 다시 뒤집어 그린다.
final class PageRenderer {
    typealias JSON = [String: Any]

    /// 그린 op와 건너뛴 op의 종류별 개수.
    private(set) var rendered: [String: Int] = [:]
    private(set) var skipped: [String: Int] = [:]
    /// 요청한 글꼴 → 실제로 쓴 글꼴. 한컴 글꼴이 맥에 없을 때의 대체 현황을 보고한다.
    private(set) var fontSubstitutions: [String: String] = [:]

    private var ctx: CGContext!
    private var fontCache: [String: CTFont] = [:]

    /// - Parameter scale: px → 출력 비트맵 배율. 2면 Retina 해상도.
    func render(layerTree: JSON, scale: CGFloat) throws -> CGImage {
        guard let width = layerTree["pageWidth"] as? Double,
              let height = layerTree["pageHeight"] as? Double,
              let root = layerTree["root"] as? JSON
        else { throw SpikeError.malformed("pageWidth/pageHeight/root 누락") }

        let pixelWidth = Int((width * scale).rounded(.up))
        let pixelHeight = Int((height * scale).rounded(.up))
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SpikeError.malformed("비트맵 컨텍스트 생성 실패") }

        // y-down 페이지 좌표로 뒤집는다. CoreGraphics 기본은 y-up이다.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)
        context.interpolationQuality = .high
        ctx = context

        drawNode(root)

        guard let image = context.makeImage() else { throw SpikeError.malformed("이미지 생성 실패") }
        return image
    }

    // MARK: - 트리 순회

    private func drawNode(_ node: JSON) {
        switch node["kind"] as? String {
        case "group":
            for child in node["children"] as? [JSON] ?? [] { drawNode(child) }
        case "clipRect":
            // 표 셀/글상자/본문 영역의 잘라내기. 자식은 이 사각형 안에서만 보인다.
            ctx.saveGState()
            if let clip = node["clip"] as? JSON { ctx.clip(to: rect(clip)) }
            if let child = node["child"] as? JSON { drawNode(child) }
            ctx.restoreGState()
        case "leaf":
            for op in node["ops"] as? [JSON] ?? [] { drawOp(op) }
        default:
            count(&skipped, "node:\(node["kind"] ?? "?")")
        }
    }

    private func drawOp(_ op: JSON) {
        let type = op["type"] as? String ?? "?"
        switch type {
        case "pageBackground": drawPageBackground(op)
        case "textRun": drawTextRun(op)
        case "line": drawLine(op)
        case "rectangle": drawRectangle(op)
        case "ellipse": drawEllipse(op)
        case "path": drawPath(op)
        case "image": drawImage(op)
        default: count(&skipped, "op:\(type)")
        }
    }

    // MARK: - 도형

    private func drawPageBackground(_ op: JSON) {
        guard let bbox = op["bbox"] as? JSON else { return }
        if let color = cgColor(op["backgroundColor"]) {
            ctx.setFillColor(color)
            ctx.fill(rect(bbox))
        }
        count(&rendered, "op:pageBackground")
    }

    private func drawLine(_ op: JSON) {
        guard let style = op["style"] as? JSON,
              let x1 = op["x1"] as? Double, let y1 = op["y1"] as? Double,
              let x2 = op["x2"] as? Double, let y2 = op["y2"] as? Double
        else { return }
        ctx.saveGState()
        applyStroke(color: style["color"], width: style["width"], dash: style["dash"])
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.strokePath()
        ctx.restoreGState()
        count(&rendered, "op:line")
    }

    private func drawRectangle(_ op: JSON) {
        guard let bbox = op["bbox"] as? JSON else { return }
        let box = rect(bbox)
        let radius = op["cornerRadius"] as? Double ?? 0
        ctx.saveGState()
        applyShapeTransform(op["transform"] as? JSON, about: box)
        let path = CGPath(
            roundedRect: box,
            cornerWidth: min(radius, box.width / 2), cornerHeight: min(radius, box.height / 2),
            transform: nil
        )
        fillAndStroke(path: path, style: op["style"] as? JSON, gradient: op["gradient"] as? JSON, bounds: box)
        ctx.restoreGState()
        count(&rendered, "op:rectangle")
    }

    private func drawEllipse(_ op: JSON) {
        guard let bbox = op["bbox"] as? JSON else { return }
        let box = rect(bbox)
        ctx.saveGState()
        applyShapeTransform(op["transform"] as? JSON, about: box)
        fillAndStroke(
            path: CGPath(ellipseIn: box, transform: nil),
            style: op["style"] as? JSON, gradient: op["gradient"] as? JSON, bounds: box
        )
        ctx.restoreGState()
        count(&rendered, "op:ellipse")
    }

    private func drawPath(_ op: JSON) {
        guard let bbox = op["bbox"] as? JSON, let commands = op["commands"] as? [JSON] else { return }
        let box = rect(bbox)
        let path = CGMutablePath()
        for command in commands {
            func value(_ key: String) -> CGFloat { CGFloat(command[key] as? Double ?? 0) }
            switch command["type"] as? String {
            case "moveTo": path.move(to: CGPoint(x: value("x"), y: value("y")))
            case "lineTo": path.addLine(to: CGPoint(x: value("x"), y: value("y")))
            case "curveTo":
                path.addCurve(
                    to: CGPoint(x: value("x3"), y: value("y3")),
                    control1: CGPoint(x: value("x1"), y: value("y1")),
                    control2: CGPoint(x: value("x2"), y: value("y2"))
                )
            case "arcTo":
                // SVG 타원호는 중심 매개변수 변환이 필요하다. 스파이크에서는 끝점까지 직선으로 근사하고
                // 몇 번 근사했는지 집계해 4단계 구현 범위를 가늠한다.
                path.addLine(to: CGPoint(x: value("x"), y: value("y")))
                count(&skipped, "path:arcTo(approximated)")
            case "closePath": path.closeSubpath()
            default: count(&skipped, "path:\(command["type"] ?? "?")")
            }
        }
        ctx.saveGState()
        applyShapeTransform(op["transform"] as? JSON, about: box)
        var style = op["style"] as? JSON
        // 선 전용 path는 lineStyle에 색/굵기가 있다.
        if let lineStyle = op["lineStyle"] as? JSON {
            style = (style ?? [:]).merging(
                ["strokeColor": lineStyle["color"] as Any, "strokeWidth": lineStyle["width"] as Any,
                 "strokeDash": lineStyle["dash"] as Any]
            ) { current, lineValue in current is NSNull ? lineValue : current }
        }
        fillAndStroke(path: path, style: style, gradient: op["gradient"] as? JSON, bounds: box)
        ctx.restoreGState()
        count(&rendered, "op:path")
    }

    /// 채우기(단색/그라데이션) 후 테두리를 그린다.
    private func fillAndStroke(path: CGPath, style: JSON?, gradient: JSON?, bounds: CGRect) {
        let opacity = CGFloat(style?["opacity"] as? Double ?? 1)
        ctx.setAlpha(opacity)

        if let gradient, fillGradient(gradient, path: path, bounds: bounds) {
            // 그라데이션이 채웠다.
        } else if let fill = cgColor(style?["fillColor"]) {
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }

        if cgColor(style?["strokeColor"]) != nil, (style?["strokeWidth"] as? Double ?? 0) > 0 {
            applyStroke(color: style?["strokeColor"], width: style?["strokeWidth"], dash: style?["strokeDash"])
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// 선형 그라데이션을 그린다. Rust SVG 렌더러와 같이 원형(type 2)만 제외하고 줄무늬(1)·원뿔(3)·
    /// 사각(4)은 선형으로 근사한다. 원형은 지원하지 않으므로 false를 돌려 호출자가 단색 채우기로
    /// 되돌아가게 한다.
    private func fillGradient(_ gradient: JSON, path: CGPath, bounds: CGRect) -> Bool {
        guard (gradient["gradientType"] as? Int) != 2,
              let hexColors = gradient["colors"] as? [String], hexColors.count >= 2,
              let positions = gradient["positions"] as? [Double], positions.count == hexColors.count
        else {
            count(&skipped, "gradient:type\(gradient["gradientType"] ?? "?")")
            return false
        }
        let colors = hexColors.compactMap { cgColor($0) }
        guard colors.count == hexColors.count,
              let cg = CGGradient(
                  colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                  colors: colors as CFArray,
                  locations: positions.map { CGFloat($0) }
              )
        else { return false }

        // 축 방향은 Rust 정본(`src/renderer/mod.rs`의 `linear_gradient_axis`)과 같다:
        // 방향 = (sin θ, -cos θ), 중심에서 정사영 길이의 절반만큼 양쪽으로 벌린다.
        // 그래서 θ=90이면 좌→우다. (처음에 θ=90을 위→아래로 가정했다가 한컴 PDF와 달라 바로잡았다.)
        // 이 규칙이 레이어 트리에는 풀려 있지 않고 각도만 실려 오므로 소비자가 각자 구현해야 한다 —
        // 2단계에서 Rust가 축 좌표를 직접 내보내도록 요청할 후보로 기록한다.
        let angle = (gradient["angle"] as? Double ?? 0) * .pi / 180
        let direction = CGVector(dx: sin(angle), dy: -cos(angle))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let half = (abs(direction.dx) * bounds.width + abs(direction.dy) * bounds.height) / 2
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(
            cg,
            start: CGPoint(x: center.x - direction.dx * half, y: center.y - direction.dy * half),
            end: CGPoint(x: center.x + direction.dx * half, y: center.y + direction.dy * half),
            options: []
        )
        ctx.restoreGState()
        return true
    }

    private func applyStroke(color: Any?, width: Any?, dash: Any?) {
        ctx.setStrokeColor(cgColor(color) ?? CGColor(gray: 0, alpha: 1))
        let lineWidth = CGFloat(width as? Double ?? 1)
        ctx.setLineWidth(lineWidth)
        switch dash as? String {
        case "dash": ctx.setLineDash(phase: 0, lengths: [lineWidth * 4, lineWidth * 2])
        case "dot": ctx.setLineDash(phase: 0, lengths: [lineWidth, lineWidth * 2])
        case "dashDot": ctx.setLineDash(phase: 0, lengths: [lineWidth * 4, lineWidth * 2, lineWidth, lineWidth * 2])
        case "dashDotDot":
            ctx.setLineDash(phase: 0, lengths: [lineWidth * 4, lineWidth * 2, lineWidth, lineWidth * 2, lineWidth, lineWidth * 2])
        default: ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    /// 도형 회전/뒤집기. 회전 중심은 bbox 중심이다.
    private func applyShapeTransform(_ transform: JSON?, about box: CGRect) {
        guard let transform else { return }
        let rotation = transform["rotation"] as? Double ?? 0
        let horz = transform["horzFlip"] as? Bool ?? false
        let vert = transform["vertFlip"] as? Bool ?? false
        guard rotation != 0 || horz || vert else { return }
        ctx.translateBy(x: box.midX, y: box.midY)
        ctx.rotate(by: CGFloat(rotation * .pi / 180))
        ctx.scaleBy(x: horz ? -1 : 1, y: vert ? -1 : 1)
        ctx.translateBy(x: -box.midX, y: -box.midY)
    }

    // MARK: - 이미지

    private func drawImage(_ op: JSON) {
        guard let bbox = op["bbox"] as? JSON,
              let base64 = op["base64"] as? String,
              let data = Data(base64Encoded: base64),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            count(&skipped, "op:image(undecodable)")
            return
        }
        let box = rect(bbox)
        ctx.saveGState()
        // y-down 컨텍스트에서 그림이 뒤집히지 않도록 bbox 안에서만 다시 뒤집는다.
        ctx.translateBy(x: box.minX, y: box.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: box.width, height: box.height))
        ctx.restoreGState()
        count(&rendered, "op:image")
    }

    // MARK: - 글자

    private func drawTextRun(_ op: JSON) {
        guard let text = op["text"] as? String, !text.isEmpty,
              let style = op["style"] as? JSON,
              let placement = op["placement"] as? JSON,
              let transform = placement["runToPage"] as? JSON,
              let originX = transform["e"] as? Double, let baselineY = transform["f"] as? Double,
              let positions = op["positions"] as? [Double]
        else {
            // 빈 문단 표식 등 글자가 없는 run은 그릴 것이 없다.
            count(&rendered, "op:textRun(empty)")
            return
        }

        let size = style["fontSize"] as? Double ?? 10
        let ratio = style["ratio"] as? Double ?? 1
        let color = cgColor(style["color"]) ?? CGColor(gray: 0, alpha: 1)
        let font = resolveFont(
            family: style["fontFamily"] as? String ?? "", size: size,
            bold: style["bold"] as? Bool ?? false, italic: style["italic"] as? Bool ?? false
        )

        ctx.saveGState()
        ctx.setFillColor(color)
        // 글자는 한 자(스칼라)씩 Rust가 계산한 위치에 놓는다. 줄 배치와 자간은 엔진의 결과를 그대로 따르고,
        // Swift는 글리프만 그린다 — 조판 결과를 두 곳에서 따로 계산하지 않기 위한 선택이다.
        let scalars = Array(text.unicodeScalars)
        for (index, scalar) in scalars.enumerated() where index < positions.count {
            let glyph = String(scalar)
            if glyph.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let line = makeLine(glyph, font: font, color: color)
            ctx.saveGState()
            ctx.translateBy(x: originX + positions[index], y: baselineY)
            // 글자는 y-up 글리프라서 y-down 컨텍스트에서 다시 뒤집고, 장평(ratio)을 가로 배율로 적용한다.
            ctx.scaleBy(x: ratio, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }

        // 밑줄/취소선: run 전체 폭 기준.
        let runWidth = positions.last ?? 0
        if (style["underline"] as? String ?? "none") != "none" {
            ctx.setStrokeColor(cgColor(style["underlineColor"]) ?? color)
            ctx.setLineWidth(max(size / 20, 0.5))
            let y = baselineY + size * 0.12
            ctx.move(to: CGPoint(x: originX, y: y))
            ctx.addLine(to: CGPoint(x: originX + runWidth, y: y))
            ctx.strokePath()
        }
        if style["strikethrough"] as? Bool ?? false {
            ctx.setStrokeColor(cgColor(style["strikeColor"]) ?? color)
            ctx.setLineWidth(max(size / 20, 0.5))
            let y = baselineY - size * 0.3
            ctx.move(to: CGPoint(x: originX, y: y))
            ctx.addLine(to: CGPoint(x: originX + runWidth, y: y))
            ctx.strokePath()
        }
        ctx.restoreGState()
        count(&rendered, "op:textRun")
    }

    private func makeLine(_ string: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// 한컴 글꼴 이름을 맥에서 쓸 수 있는 글꼴로 해석한다.
    /// 설치되지 않은 글꼴은 명조/바탕 계열이면 AppleMyungjo, 그 밖에는 Apple SD Gothic Neo로 대체한다.
    /// 대체 사실은 `fontSubstitutions`에 남겨 보고서에서 충실도 한계로 드러낸다.
    private func resolveFont(family: String, size: Double, bold: Bool, italic: Bool) -> CTFont {
        let key = "\(family)|\(size)|\(bold)|\(italic)"
        if let cached = fontCache[key] { return cached }

        var resolved = CTFontCreateWithName(family as CFString, size, nil)
        let actualFamily = CTFontCopyFamilyName(resolved) as String
        if actualFamily.caseInsensitiveCompare(family) != .orderedSame {
            let serif = ["명조", "바탕", "myungjo", "batang", "serif"].contains { family.lowercased().contains($0) }
            let fallback = serif ? "AppleMyungjo" : "Apple SD Gothic Neo"
            resolved = CTFontCreateWithName(fallback as CFString, size, nil)
            fontSubstitutions[family] = CTFontCopyFamilyName(resolved) as String
        }

        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty,
           let styled = CTFontCreateCopyWithSymbolicTraits(resolved, size, nil, traits, traits) {
            resolved = styled
        }
        fontCache[key] = resolved
        return resolved
    }

    // MARK: - 보조

    private func rect(_ json: JSON) -> CGRect {
        CGRect(
            x: json["x"] as? Double ?? 0, y: json["y"] as? Double ?? 0,
            width: json["width"] as? Double ?? 0, height: json["height"] as? Double ?? 0
        )
    }

    /// `#rrggbb` 형식의 CSS 색을 CGColor로 바꾼다. null/비문자열이면 nil.
    private func cgColor(_ value: Any?) -> CGColor? {
        guard let css = value as? String, css.hasPrefix("#"), css.count == 7,
              let rgb = UInt32(css.dropFirst(), radix: 16)
        else { return nil }
        return CGColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1
        )
    }

    private func count(_ table: inout [String: Int], _ key: String) {
        table[key, default: 0] += 1
    }
}

/// CGImage를 PNG 파일로 저장한다.
func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw SpikeError.malformed("PNG 대상 생성 실패") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw SpikeError.malformed("PNG 저장 실패") }
}

import CoreGraphics
import Foundation
import ImageIO
import RhwpKit

/// 그림(`image` op). 채우기 방식, 잘라내기, 투명도, 회전·뒤집기를 엔진의 SVG 렌더러(`render_image_node`)와 같은
/// 규칙으로 그린다. 규칙이 두 곳에 있는 **중복 위험**이 있으니 엔진 쪽이 바뀌면 여기도 고친다.
extension Drawing {
    mutating func drawImage(_ op: ImageOp) {
        let box = Self.unrotatedFrame(of: op)
        // 잘라내기 선택이 가로로 비어 있으면 틀만 차지하고 원본은 그리지 않는다(엔진이 한컴 동작이라고 적어 둔 규칙).
        // 세로가 비었거나 뒤집힌 경우(`bottom <= top`)는 다르다. 엔진의 SVG 렌더러는 이것도 그리지 않지만,
        // 한컴 PDF는 이 경우 그림 전체를 그린다(`156564340-ip-dispute-mediation-poster-slice`의 로고: crop
        // `(0, 6240, 304, 2619)`, 전체를 그렸을 때 실루엣 일치율 100%, 건너뛰면 79%). 증거를 따라 이 경우는 잘라내기를
        // 무시하고 전체를 그린다. 가로가 빈 경우의 한컴 동작은 이 샘플 세트에 자료가 없어 미검증이다.
        var crop = op.crop
        if let selection = crop {
            if selection.right <= selection.left {
                report.countRendered("op:image(emptyCrop)")
                return
            }
            if selection.bottom <= selection.top { crop = nil }
        }
        guard let data = op.imageData, !data.isEmpty else {
            drawMissingImage(box, omitted: op.imageBytesOmitted)
            return
        }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        applyShapeTransform(op.transform, about: box)
        ctx.setAlpha(min(max(op.opacity, 0), 1))
        reportUnsupportedEffects(op)

        let fillMode = op.fillMode ?? "fitToSize"

        // WMF·EMF 등을 엔진이 SVG 그림으로 바꿔 보낸 경우. CoreGraphics는 SVG를 읽지 못하므로 SVG 조각 렌더러로 그린다.
        // 채우기 방식이 늘이기(fitToSize/total)이면 엔진도 `preserveAspectRatio="none"`으로 상자에 맞춘다.
        if op.mime == "image/svg+xml", let svg = String(data: data, encoding: .utf8) {
            let stretch = fillMode == "fitToSize" || fillMode == "total"
            report.merge(SVGFragmentDrawer.drawSVGImage(
                svg, in: box, preserveAspect: !stretch, context: ctx, fontResolver: fontResolver
            ))
            report.countRendered("op:image(svg)")
            return
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            report.countSkipped("op:image(undecodable)")
            return
        }
        let size = CGSize(width: image.width, height: image.height)

        switch fillMode {
        case "zoom", "none":
            // 종횡비를 지켜 상자 안에 맞춘다. 잘라내기가 있으면 보이는 영역 기준으로 맞춘다(채우기 유형 15도 같다).
            let visible = crop.map { Self.cropSource($0, referenceHU: op.originalSizeHU, imageSize: size) }
                ?? CGRect(origin: .zero, size: size)
            guard visible.width > 0, visible.height > 0 else { return }
            let scale = min(box.width / visible.width, box.height / visible.height)
            let fitted = CGSize(width: visible.width * scale, height: visible.height * scale)
            drawRegion(
                image, source: visible,
                into: CGRect(
                    x: box.midX - fitted.width / 2, y: box.midY - fitted.height / 2,
                    width: fitted.width, height: fitted.height
                )
            )
        case "fitToSize", "total":
            // 잘라내기가 있으면 원본의 그 부분만 상자에 늘여 채운다. 잘린 것이 없으면 전체를 늘인다.
            var visible = CGRect(origin: .zero, size: size)
            if let crop {
                let rect = Self.cropSource(crop, referenceHU: op.originalSizeHU, imageSize: size)
                let isCropped = rect.minX > 0.5 || rect.minY > 0.5 || abs(rect.width - size.width) > 1
                    || abs(rect.height - size.height) > 1
                if isCropped { visible = rect }
            }
            drawRegion(image, source: visible, into: box)
        case "tileAll": drawTiled(image, in: box, tileSize: tileSize(op, image), horizontal: true, vertical: true)
        case "tileHorzTop", "tileHorzBottom":
            drawTiled(image, in: box, tileSize: tileSize(op, image), horizontal: true, vertical: false)
        case "tileVertLeft", "tileVertRight":
            drawTiled(image, in: box, tileSize: tileSize(op, image), horizontal: false, vertical: true)
        default:
            // 배치 모드(가운데, 왼쪽 위 …): 원래 크기로 정렬해 놓고 상자로 자른다.
            let natural = tileSize(op, image)
            let origin = Self.alignedOrigin(mode: fillMode, in: box, size: natural)
            ctx.clip(to: box)
            drawRegion(
                image, source: CGRect(origin: .zero, size: size),
                into: CGRect(origin: origin, size: natural)
            )
        }
        report.countRendered("op:image")
    }

    // MARK: - 보조

    /// 90°·270° 회전한 그림이 그려질 **회전 전** 틀. HWPX의 크기는 회전 후 외접 사각형이라 세로 그림을 90° 돌리면
    /// bbox가 가로로 들어온다. 그 위에 회전을 또 적용하면 이중 회전이 되어 그림이 엉뚱한 곳으로 나가므로(실제
    /// 문서에서 확인) 가로·세로를 맞바꾼 틀을 같은 중심에 두고 그 위에서 회전한다. 엔진의
    /// `ShapeTransform::effective_image_bbox`와 같은 규칙이다. 그 밖의 각도는 bbox를 그대로 쓴다.
    static func unrotatedFrame(of op: ImageOp) -> CGRect {
        let angle = op.transform.rotation.truncatingRemainder(dividingBy: 360)
        let normalized = angle < 0 ? angle + 360 : angle
        guard abs(normalized - 90) < 1 || abs(normalized - 270) < 1 else { return op.bbox.cgRect }
        let box = op.bbox.cgRect
        return CGRect(x: box.midX - box.height / 2, y: box.midY - box.width / 2, width: box.height, height: box.width)
    }

    /// 엔진은 자리 표시를 점선 사각형으로 그린다(한컴 2024 뷰어와 같다). 바이트를 일부러 생략한 요청이면 그리지 않는다.
    private mutating func drawMissingImage(_ box: CGRect, omitted: Bool) {
        guard !omitted else {
            report.countSkipped("op:image(bytesOmitted)")
            return
        }
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255, alpha: 1))
        ctx.fill(box)
        ctx.setStrokeColor(CGColor(srgbRed: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255, alpha: 1))
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.stroke(box)
        ctx.restoreGState()
        report.countRendered("op:image(placeholder)")
    }

    /// 밝기·대비와 그림 효과는 아직 적용하지 못한다. 그림은 원본 색으로 그리고 집계한다.
    private mutating func reportUnsupportedEffects(_ op: ImageOp) {
        if op.effect != "realPic" { report.countSkipped("image:effect(\(op.effect))") }
        if op.brightness != 0 || op.contrast != 0 { report.countSkipped("image:brightnessContrast") }
    }

    /// 배치·타일 모드의 원래 크기(px). 엔진은 개체 저장 크기를 우선하고 없으면 그림 픽셀 크기를 쓴다.
    private func tileSize(_ op: ImageOp, _ image: CGImage) -> CGSize {
        if let size = op.originalSize, size.width > 0, size.height > 0 {
            return CGSize(width: size.width, height: size.height)
        }
        return CGSize(width: image.width, height: image.height)
    }

    private static func alignedOrigin(mode: String, in box: CGRect, size: CGSize) -> CGPoint {
        let x: CGFloat
        switch mode {
        case "leftTop", "leftCenter", "leftBottom": x = box.minX
        case "rightTop", "rightCenter", "rightBottom": x = box.maxX - size.width
        default: x = box.minX + (box.width - size.width) / 2
        }
        let y: CGFloat
        switch mode {
        case "leftTop", "centerTop", "rightTop": y = box.minY
        case "leftBottom", "centerBottom", "rightBottom": y = box.maxY - size.height
        default: y = box.minY + (box.height - size.height) / 2
        }
        return CGPoint(x: x, y: y)
    }

    /// 원본 그림 `source`(그림 픽셀, 원점 왼쪽 위) 영역을 `dest`에 늘여 그린다. 그림 밖으로 나간 부분은 비워 둔다.
    private func drawRegion(_ image: CGImage, source: CGRect, into dest: CGRect) {
        guard source.width > 0, source.height > 0, dest.width > 0, dest.height > 0 else { return }
        let visible = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !visible.isNull, visible.width > 0, visible.height > 0, let piece = image.cropping(to: visible) else { return }
        // 잘린 조각이 놓일 자리: 원래 대응 관계(source → dest)를 유지한다.
        let scaleX = dest.width / source.width
        let scaleY = dest.height / source.height
        let target = CGRect(
            x: dest.minX + (visible.minX - source.minX) * scaleX, y: dest.minY + (visible.minY - source.minY) * scaleY,
            width: visible.width * scaleX, height: visible.height * scaleY
        )
        ctx.saveGState()
        // 그림 영역 밖으로 번지지 않게 자른다(`dest`가 보이는 상자다).
        ctx.clip(to: dest)
        // y-down 컨텍스트에서 그림이 뒤집히지 않도록 그 자리에서만 다시 뒤집는다.
        ctx.translateBy(x: target.minX, y: target.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(piece, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        ctx.restoreGState()
    }

    /// 바둑판 채우기. 타일은 상자 왼쪽 위에서 시작한다. 한 방향만 타일링하면 다른 방향은 한 번만 놓는다.
    private func drawTiled(_ image: CGImage, in box: CGRect, tileSize: CGSize, horizontal: Bool, vertical: Bool) {
        guard tileSize.width > 0, tileSize.height > 0 else { return }
        let columns = horizontal ? Int((box.width / tileSize.width).rounded(.up)) : 1
        let rows = vertical ? Int((box.height / tileSize.height).rounded(.up)) : 1
        // 작은 타일이 큰 상자를 덮는 악성·손상 입력이 수백만 번 그리지 못하게 막는다.
        guard columns * rows <= 4096 else {
            drawRegion(image, source: CGRect(x: 0, y: 0, width: image.width, height: image.height), into: box)
            return
        }
        ctx.saveGState()
        ctx.clip(to: box)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let tile = CGRect(
                    x: box.minX + CGFloat(column) * tileSize.width, y: box.minY + CGFloat(row) * tileSize.height,
                    width: tileSize.width, height: tileSize.height
                )
                drawRegion(image, source: CGRect(x: 0, y: 0, width: image.width, height: image.height), into: tile)
            }
        }
        ctx.restoreGState()
    }

    /// 잘라내기 좌표(HWPUNIT)를 원본 그림 픽셀 영역으로 바꾼다. 엔진의 `compute_image_crop_src`를 옮긴 것이다.
    ///
    /// 좌표 기준 크기(`referenceHU`)를 알면 그 대비 그림 픽셀 수로 배율을 정한다. 모르면 `right`·`bottom`이 **그 축을
    /// 자르지 않았을 때의 전체 범위**라는 가정으로 축마다 배율을 추정하고(한 축만 확인되면 두 축에 쓴다), 그것도
    /// 안 되면 표준 75 HU/px를 쓴다.
    static func cropSource(_ crop: ImageOp.ImageCrop, referenceHU: [Int]?, imageSize: CGSize) -> CGRect {
        let left = Double(crop.left), top = Double(crop.top), right = Double(crop.right), bottom = Double(crop.bottom)
        let imageWidth = Double(imageSize.width), imageHeight = Double(imageSize.height)

        func valid(_ scale: Double) -> Bool { scale.isFinite && scale > 0 }

        var scale: (x: Double, y: Double)?
        if let reference = referenceHU, reference.count == 2, reference[0] > 0, reference[1] > 0,
           imageWidth > 0, imageHeight > 0 {
            let candidate = (x: Double(reference[0]) / imageWidth, y: Double(reference[1]) / imageHeight)
            if valid(candidate.x), valid(candidate.y) { scale = candidate }
        }
        if scale == nil {
            func axis(_ start: Double, _ end: Double, _ pixels: Double) -> Double? {
                guard start == 0, end > 0, pixels > 0 else { return nil }
                let value = end / pixels
                return valid(value) ? value : nil
            }
            switch (axis(left, right, imageWidth), axis(top, bottom, imageHeight)) {
            case let (x?, y?): scale = (x, y)
            case let (x?, nil): scale = (x, x)
            case let (nil, y?): scale = (y, y)
            case (nil, nil): scale = nil
            }
        }
        let resolved = scale ?? (75, 75)
        return CGRect(
            x: left / resolved.x, y: top / resolved.y,
            width: (right - left) / resolved.x, height: (bottom - top) / resolved.y
        )
    }
}

import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender
import Testing

// 타일 렌더링의 약속: **타일을 이어 붙이면 쪽을 통째로 그린 비트맵과 같은 모습이다.**
//
// 기대값은 구현이 아니라 두 가지 독립 기준이다.
// 1. 통째 렌더(`render(_:scale:)`, 한컴 PDF와 대조해 온 경로). 타일은 컨텍스트를 정수 픽셀만 옮기므로 같은 부분 픽셀 위치에
//    그려진다. 같은 크기의 비트맵 안에서 정수만큼 옮겨 그리면 CoreGraphics는 비트 단위로 같은 결과를 낸다(0단계 탐침으로 확인).
// 2. 해석적 기하. 선분이 픽셀을 덮는 비율을 부분 표본으로 직접 계산한다.
//
// **정확히 같은 것과 그렇지 않은 것을 가른다.** 타일 컨텍스트는 통째 비트맵보다 작아서 CoreGraphics가 "그릴 범위"를 다르게 잡는다.
// 그 결과 축에 나란한 도형·가로세로선·90° 회전·반투명·글자·그림·잘라내기는 **비트 단위로 같지만**(아래 `exact*` 시험),
// 기울어진 변·곡선의 안티앨리어싱과 그라데이션 표본은 몇 단계 다르다(`smooth*`·`slanted*`). 이 차이는 타일 가장자리가 아니라
// 타일 안쪽에 고르게 퍼져 있어 이음매 줄이 아니다. 그리고 어긋난 픽셀에서 해석적 덮임과 견주면 **타일이 통째 렌더보다 정답에
// 가깝다**(긴 대각선 0.002 대 0.014, 배율 14에서는 0.013 대 0.13이고 통째 렌더는 정답이 111인 픽셀을 255로 칠한다). 그래서
// 기울어진 변의 기준은 통째 렌더가 아니라 해석적 기하다.

// MARK: - 손으로 만든 op

/// 타일 경계(어떤 타일 크기로도)를 가로지르도록 흩어 놓을 op들. JSON에 `"#rrggbb"`가 들어가므로 `##"…"##`를 쓴다.
private enum Ops {
    static func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> String {
        ##"{"x":\##(x),"y":\##(y),"width":\##(w),"height":\##(h)}"##
    }

    static func style(fill: String?, stroke: String? = nil, width: Double = 0, dash: String = "solid", opacity: Double = 1) -> String {
        let fillJSON = fill.map { "\"\($0)\"" } ?? "null"
        let strokeJSON = stroke.map { "\"\($0)\"" } ?? "null"
        return ##"{"fillColor":\##(fillJSON),"strokeColor":\##(strokeJSON),"strokeWidth":\##(width),"strokeDash":"\##(dash)","opacity":\##(opacity)}"##
    }

    static func transform(rotation: Double = 0) -> String {
        ##"{"rotation":\##(rotation),"horzFlip":false,"vertFlip":false}"##
    }

    static func background(width: Double = 200, height: Double = 140) -> String {
        ##"{"type":"pageBackground","bbox":\##(box(0, 0, width, height)),"backgroundColor":"#ffffff"}"##
    }

    static func rect(
        _ x: Double, _ y: Double, _ w: Double, _ h: Double, fill: String?, stroke: String? = nil, width: Double = 0,
        opacity: Double = 1, radius: Double = 0, rotation: Double = 0, gradient: String? = nil
    ) -> String {
        let gradientJSON = gradient.map { ##","gradient":\##($0)"## } ?? ""
        return ##"{"type":"rectangle","bbox":\##(box(x, y, w, h)),"cornerRadius":\##(radius),"style":\##(style(fill: fill, stroke: stroke, width: width, opacity: opacity)),"transform":\##(transform(rotation: rotation))\##(gradientJSON)}"##
    }

    static func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double, fill: String, stroke: String, width: Double, gradient: String) -> String {
        ##"{"type":"ellipse","bbox":\##(box(x, y, w, h)),"style":\##(style(fill: fill, stroke: stroke, width: width)),"gradient":\##(gradient),"transform":\##(transform())}"##
    }

    static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, color: String = "#000000", width: Double, dash: String = "solid") -> String {
        let x = min(x1, x2), y = min(y1, y2)
        return ##"{"type":"line","bbox":\##(box(x, y, abs(x2 - x1), abs(y2 - y1))),"x1":\##(x1),"y1":\##(y1),"x2":\##(x2),"y2":\##(y2),"style":{"color":"\##(color)","width":\##(width),"dash":"\##(dash)"}}"##
    }

    static func path(commands: String, fill: String?, stroke: String?, width: Double) -> String {
        ##"{"type":"path","bbox":\##(box(10, 10, 180, 120)),"commands":[\##(commands)],"style":\##(style(fill: fill, stroke: stroke, width: width)),"transform":\##(transform())}"##
    }

    static func text(_ string: String, size: Double, originX: Double, baseline: Double, step: Double) -> String {
        OpJSON.textRun(
            string, font: "Helvetica", size: size, originX: originX, baseline: baseline,
            positions: (0..<string.unicodeScalars.count).map { Double($0) * step }
        )
    }

    static let radialGradient = ##"{"gradientType":2,"angle":0,"centerX":40,"centerY":60,"colors":["#ffee00","#0044aa"],"positions":[0,1]}"##
    static let stripeGradient = ##"{"gradientType":1,"angle":45,"centerX":50,"centerY":50,"colors":["#ff0000","#00cc00"],"positions":[0,1]}"##

    /// 스스로 그린 16×16 PNG(빨강·파랑 칸과 초록 그라데이션)를 `image` op로 만든다. 늘려 그릴 때의 리샘플링을 본다.
    static func image(_ x: Double, _ y: Double, _ w: Double, _ h: Double) throws -> String {
        let swatch = try PageRenderer().render(
            makeLeafTree(ops: [
                OpJSON.background("#ffffff", size: 16),
                OpJSON.rectangle(x: 0, y: 0, w: 8, h: 8, fill: "#ff0000"),
                OpJSON.rectangle(x: 8, y: 8, w: 8, h: 8, fill: "#0000ff"),
                OpJSON.rectangle(x: 4, y: 4, w: 8, h: 8, fill: "#00aa00", gradient: OpJSON.linearGradient(angle: 90, from: "#00aa00", to: "#ffff00")),
            ], width: 16, height: 16),
            scale: 1
        )
        let png = try #require(swatch.pngData()).base64EncodedString()
        return ##"{"type":"image","bbox":\##(box(x, y, w, h)),"mime":"image/png","base64":"\##(png)"}"##
    }

    /// 잘라내기: 자식이 사각형보다 훨씬 크게 그려져도 안쪽만 보인다. 잘라내기 사각형 가장자리는 소수 좌표다.
    static func clippedGroup(ops: [String]) -> String {
        let child = leaf(ops: [
            rect(0, 0, 200, 140, fill: "#00ffff", opacity: 0.6),
            text("CLIPPED", size: 36, originX: 100, baseline: 84, step: 26),
        ])
        let clip = ##"{"kind":"clipRect","bounds":\##(box(0, 0, 200, 140)),"clip":\##(box(105.5, 30.5, 70, 60)),"clipKind":"tableCell","child":\##(child)}"##
        return ##"{"kind":"group","groupKind":{"kind":"generic"},"bounds":\##(box(0, 0, 200, 140)),"children":[\##(leaf(ops: ops, width: 200, height: 140)),\##(clip)]}"##
    }
}

/// 축에 나란한 도형, 가로세로선(굵은 선 포함), 90° 회전, 반투명, 글자, 그림, 잘라내기. **통째 렌더와 비트 단위로 같아야 한다.**
private func exactPage() throws -> PageLayerTree {
    try makeTree(Ops.clippedGroup(ops: [
        Ops.background(),
        Ops.rect(20.3, 10.7, 120, 50, fill: "#3366cc", stroke: "#000000", width: 2.5),
        Ops.rect(50, 20, 100, 90, fill: "#cc00cc", opacity: 0.5),
        Ops.line(15, 70, 185, 70, color: "#006600", width: 14),
        Ops.line(160, 5, 160, 135, width: 3),
        // bbox는 100×10인데 90° 회전하면 세로로 서서 위아래 45px씩 bbox 밖으로 번진다.
        Ops.rect(145, 65, 100, 10, fill: "#222222", rotation: 90),
        try Ops.image(30.2, 55.4, 59.2, 59.2),
        Ops.text("Hamburgefonstiv Quick", size: 28, originX: 6, baseline: 56, step: 14.5),
        Ops.text("tile boundary glyphs", size: 9, originX: 12, baseline: 132, step: 5.2),
    ]), width: 200, height: 140)
}

/// 점선, 그라데이션, 타원·둥근 모서리: 통째 렌더와 한 단계 안팎으로 같다. 대시 경계와 그라데이션 표본, 곡선 테두리의
/// 안티앨리어싱 덮임이 부분 픽셀 위치에서 반올림되는 방식이 컨텍스트 크기에 조금 기댄다.
private func smoothPage() throws -> PageLayerTree {
    try makeLeafTree(ops: [
        Ops.background(),
        Ops.rect(10, 90, 90, 40, fill: "#000000", gradient: Ops.stripeGradient),
        Ops.rect(20.3, 10.7, 120, 50, fill: "#3366cc", stroke: "#000000", width: 2.5, radius: 6),
        Ops.ellipse(70.5, 40.2, 110, 80, fill: "#000000", stroke: "#aa2200", width: 3, gradient: Ops.radialGradient),
        Ops.line(15, 70, 185, 70, color: "#006600", width: 14, dash: "dash"),
    ], width: 200, height: 140)
}

/// 기울어진 변: 대각선, 임의 각도 회전, 삼각형, 쪽 밖까지 제어점이 가는 큰 곡선. 통째 렌더와 최대 16단계 안쪽으로 같다
/// (한도의 근거는 아래 시험들).
private func slantedPage() throws -> PageLayerTree {
    try makeLeafTree(ops: [
        Ops.background(),
        Ops.path(commands: ##"""
        {"type":"moveTo","x":10,"y":120},{"type":"curveTo","x1":60,"y1":-40,"x2":130,"y2":220,"x3":190,"y3":20},
        {"type":"arcTo","x":150,"y":130,"rx":40,"ry":25,"rotation":20,"largeArc":true,"sweep":false},{"type":"closePath"}
        """##, fill: nil, stroke: "#990000", width: 4),
        Ops.line(5, 5, 195, 135, width: 1),
        Ops.line(195, 5, 5, 135, color: "#aa0000", width: 6),
        Ops.rect(100, 100, 60, 25, fill: "#ff8800", stroke: "#000000", width: 1, radius: 3, rotation: 30),
        Ops.path(commands: ##"{"type":"moveTo","x":10,"y":120},{"type":"lineTo","x":100,"y":10},{"type":"lineTo","x":190,"y":120},{"type":"closePath"}"##, fill: "#336699", stroke: nil, width: 0),
    ], width: 200, height: 140)
}

// MARK: - 타일 합성

/// 통째 렌더와 타일 합성의 비교. 같지 않은 픽셀이 있으면 처음 어긋난 위치를 담는다.
private struct Comparison: CustomStringConvertible {
    var tiles = 0
    var differing = 0
    var maxDelta = 0
    var first: String?

    var description: String {
        "타일 \(tiles)장, 다른 픽셀 \(differing)개, 최대 채널 차이 \(maxDelta), 처음 \(first ?? "없음")"
    }
}

/// 모든 타일을 그려 하나의 비트맵으로 이어 붙인다. 뷰어가 화면에 타일을 늘어놓는 것과 같은 일이다.
private func compose(_ tree: PageLayerTree, scale: Double, tileSize: Int) throws -> (pixels: Pixels, tiles: Int) {
    let renderer = PageRenderer()
    let grid = TileGrid(pageWidth: tree.pageWidth, pageHeight: tree.pageHeight, scale: scale, tileSize: tileSize)
    let canvas = try #require(CGContext(
        data: nil, width: grid.pixelWidth, height: grid.pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    canvas.interpolationQuality = .none
    for row in 0..<grid.rows {
        for column in 0..<grid.columns {
            let rect = try #require(grid.rect(of: TileIndex(column: column, row: row)))
            let tile = try renderer.renderTile(tree, scale: scale, tile: rect).image
            #expect(tile.width == rect.width && tile.height == rect.height)
            // CoreGraphics 의 y 는 위로 늘어나므로 비트맵 위에서 rect.y 만큼 내려온 타일의 아래 변은 H - rect.maxY 다.
            canvas.draw(tile, in: CGRect(x: rect.x, y: grid.pixelHeight - rect.maxY, width: rect.width, height: rect.height))
        }
    }
    return (Pixels(try #require(canvas.makeImage())), grid.tileCount)
}

/// 통째 렌더와 타일 합성을 픽셀 단위로 견준다.
private func compare(_ tree: PageLayerTree, scale: Double, tileSize: Int) throws -> Comparison {
    let full = try Pixels(PageRenderer().render(tree, scale: scale).image)
    let (composite, tiles) = try compose(tree, scale: scale, tileSize: tileSize)
    #expect(full.width == composite.width && full.height == composite.height, "합성한 크기가 통째 렌더와 다르다")
    let diff = full.compare(composite, atX: 0, y: 0)
    var result = Comparison(tiles: tiles, differing: diff.differing, maxDelta: diff.maxDelta)
    if let first = diff.first { result.first = "(\(first.x), \(first.y))" }
    return result
}

/// 걸러내기 없이, 통째 렌더의 변환을 그대로 쓰되 장치 공간에서 정수 픽셀만 옮긴 컨텍스트에 그린다.
/// `renderTile`의 변환 식과 다른 식으로(옮기기를 쪽 비트맵 변환 **앞**에 둔다) 같은 사상을 만든다.
private func renderTileWithoutCulling(_ tree: PageLayerTree, scale: Double, tile: PixelRect) throws -> CGImage {
    let fullHeight = Int(((tree.pageHeight * scale).rounded(.up)))
    let context = try #require(CGContext(
        data: nil, width: tile.width, height: tile.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.translateBy(x: CGFloat(-tile.x), y: CGFloat(tile.height + tile.y - fullHeight))
    context.translateBy(x: 0, y: CGFloat(fullHeight))
    context.scaleBy(x: scale, y: -scale)
    PageRenderer().draw(tree, into: context)
    return try #require(context.makeImage())
}

/// 배율 × 타일 크기. 37px는 어떤 배율의 정수 경계와도 맞지 않는 소수(素數)다. 512는 쪽보다 큰 타일(한 장)이다.
private let scaleAndTileSize: [(scale: Double, tileSize: Int)] = [
    (1, 64), (1, 37), (1, 512), (1.37, 64), (1.37, 37), (2.5, 64), (2.5, 37), (2.5, 512), (0.5, 37),
]

@Suite("타일 합성 vs 통째 렌더 — 손으로 만든 쪽")
struct TileCompositionTests {
    @Test("축에 나란한 도형·선·글자·그림·잘라내기는 통째 렌더와 비트 단위로 같다", arguments: scaleAndTileSize)
    func exactContentIsBitIdentical(scale: Double, tileSize: Int) throws {
        let result = try compare(exactPage(), scale: scale, tileSize: tileSize)
        #expect(result.tiles > 0)
        #expect(result.differing == 0, "배율 \(scale), 타일 \(tileSize)px: \(result)")
    }

    @Test("점선·그라데이션·타원은 통째 렌더와 2단계 안쪽으로 같다", arguments: scaleAndTileSize)
    func smoothContentDiffersByQuantizationOnly(scale: Double, tileSize: Int) throws {
        let result = try compare(smoothPage(), scale: scale, tileSize: tileSize)
        // 관측: 최대 1단계(8비트 덮임이 한 칸 반올림되는 차이). 2는 그 위에 둔 한 칸 여유다.
        #expect(result.maxDelta <= 2, "배율 \(scale), 타일 \(tileSize)px: \(result)")
    }

    @Test("기울어진 변은 통째 렌더와 16단계 안쪽으로 같다", arguments: scaleAndTileSize)
    func slantedEdgesStayWithinTolerance(scale: Double, tileSize: Int) throws {
        let result = try compare(slantedPage(), scale: scale, tileSize: tileSize)
        // 관측: 대각선 15, 30° 회전 사각형 7, 큰 곡선 5, 삼각형 4. 어긋난 쪽이 통째 렌더라는 근거는 아래 해석적 시험이다.
        // 16은 그 관측 위에 둔 상한이다. 타일 이동이 1px만 틀려도 기울어진 변의 차이는 100을 넘으므로 이 한도로 걸러진다.
        #expect(result.maxDelta <= 16, "배율 \(scale), 타일 \(tileSize)px: \(result)")
    }

    @Test("걸러내기는 결과를 바꾸지 않는다: 걸러낸 타일 = 걸러내지 않은 타일(같은 크기 비트맵이라 비트 단위로 같다)")
    func cullingKeepsPixels() throws {
        let renderer = PageRenderer()
        var compared = 0
        for tree in try [exactPage(), smoothPage(), slantedPage()] {
            let grid = TileGrid(pageWidth: tree.pageWidth, pageHeight: tree.pageHeight, scale: 2.5, tileSize: 41)
            for row in 0..<grid.rows {
                for column in 0..<grid.columns {
                    let rect = try #require(grid.rect(of: TileIndex(column: column, row: row)))
                    let culled = try Pixels(renderer.renderTile(tree, scale: 2.5, tile: rect).image)
                    let everything = try Pixels(renderTileWithoutCulling(tree, scale: 2.5, tile: rect))
                    let diff = everything.compare(culled, atX: 0, y: 0)
                    #expect(diff.differing == 0, "타일 \(column),\(row): 다른 픽셀 \(diff.differing), 최대 차이 \(diff.maxDelta)")
                    compared += 1
                }
            }
        }
        #expect(compared > 300)
    }

    @Test("타일은 보이는 영역과 겹치는 op만 그리고 먼 op는 집계에도 들어가지 않는다")
    func cullingSkipsFarOps() throws {
        // 쪽 왼쪽 위와 오른쪽 아래에 사각형이 하나씩.
        let tree = try makeLeafTree(ops: [
            OpJSON.background(size: 1000),
            OpJSON.rectangle(x: 10, y: 10, w: 20, h: 20, fill: "#ff0000"),
            OpJSON.rectangle(x: 900, y: 900, w: 20, h: 20, fill: "#0000ff"),
        ], width: 1000, height: 1000)
        let renderer = PageRenderer()
        // 왼쪽 위 타일(0..<100px): 배경과 빨간 사각형. 파란 사각형은 걸러진다.
        let nearTopLeft = try renderer.renderTile(tree, scale: 1, tile: PixelRect(x: 0, y: 0, width: 100, height: 100))
        #expect(nearTopLeft.report.rendered["op:rectangle"] == 1)
        #expect(Pixels(nearTopLeft.image).rgb(20, 20) == (255, 0, 0))
        // 오른쪽 아래 타일: 파란 사각형만.
        let nearBottomRight = try renderer.renderTile(tree, scale: 1, tile: PixelRect(x: 850, y: 850, width: 100, height: 100))
        #expect(nearBottomRight.report.rendered["op:rectangle"] == 1)
        #expect(Pixels(nearBottomRight.image).rgb(60, 60) == (0, 0, 255))
        // 가운데 타일: 둘 다 걸러진다. 배경만 그려진다.
        let middle = try renderer.renderTile(tree, scale: 1, tile: PixelRect(x: 400, y: 400, width: 100, height: 100))
        #expect(middle.report.rendered["op:rectangle"] == nil)
        #expect(middle.report.rendered["op:pageBackground"] == 1)
    }

    @Test("잘라내기 영역이 타일과 겹치지 않으면 자식을 하나도 그리지 않는다")
    func clipSubtreesAreSkipped() throws {
        let child = leaf(ops: [OpJSON.rectangle(x: 0, y: 0, w: 400, h: 400, fill: "#0000ff")], width: 400, height: 400)
        let clip = ##"{"kind":"clipRect","bounds":{"x":0,"y":0,"width":400,"height":400},"clip":{"x":300,"y":300,"width":50,"height":50},"clipKind":"generic","child":\##(child)}"##
        let tree = try makeTree(clip, width: 400, height: 400)
        let renderer = PageRenderer()
        let away = try renderer.renderTile(tree, scale: 1, tile: PixelRect(x: 0, y: 0, width: 100, height: 100))
        #expect(away.report.rendered.isEmpty, "겹치지 않는 잘라내기는 자식을 순회하지 않는다: \(away.report.rendered)")
        let inside = try renderer.renderTile(tree, scale: 1, tile: PixelRect(x: 300, y: 300, width: 100, height: 100))
        #expect(inside.report.rendered["op:rectangle"] == 1)
        #expect(Pixels(inside.image).rgb(10, 10) == (0, 0, 255))
        #expect(Pixels(inside.image).rgb(80, 80) == (0, 0, 0), "잘라내기 밖은 칠하지 않는다(투명 검정)")
    }

    @Test("회전한 도형은 bbox 밖으로 번져도 걸러지지 않는다")
    func rotatedShapesAreNotCulledByTheirBox() throws {
        // bbox는 가로로 긴 150..250 × 100..110인데 90° 회전하면 중심 (200, 105)에서 세로로 서서 y 55..155를 칠한다.
        let tree = try makeLeafTree(ops: [
            OpJSON.background(size: 300),
            Ops.rect(150, 100, 100, 10, fill: "#ff0000", rotation: 90),
        ], width: 300, height: 300)
        // 타일 y 0..<60 은 bbox(+여백 24)와 겹치지 않지만 회전한 막대의 아래 5줄(y 55..<60)이 닿는다.
        let tile = try PageRenderer().renderTile(tree, scale: 1, tile: PixelRect(x: 180, y: 0, width: 40, height: 60))
        #expect(Pixels(tile.image).rgb(20, 58) == (255, 0, 0))
        #expect(tile.report.rendered["op:rectangle"] == 1)
    }

    @Test("한 변이 16384px를 넘는 쪽도 타일은 그린다: 맨 끝 타일의 위치와 색")
    func tileFarFromTheOrigin() throws {
        // 300×200 쪽 @60배 = 18000×12000(통째 렌더는 거부한다). 오른쪽 아래 구석 쪽 좌표 1×1px 사각형을 빨갛게 하면
        // 비트맵 (17940..<18000, 11940..<12000) 의 60×60px 가 칠해진다.
        let tree = try makeLeafTree(ops: [
            OpJSON.background("#ffffff", size: 300),
            OpJSON.rectangle(x: 299, y: 199, w: 1, h: 1, fill: "#ff0000"),
        ], width: 300, height: 200)
        #expect(throws: RenderError.self) { _ = try PageRenderer().render(tree, scale: 60) }

        let grid = TileGrid(pageWidth: 300, pageHeight: 200, scale: 60)
        #expect((grid.pixelWidth, grid.pixelHeight) == (18000, 12000))
        // 마지막 타일은 비트맵 (17920, 11776) 에서 시작하는 80×224px 다. 사각형은 그 안 (20, 164) 에서 시작한다.
        let last = TileIndex(column: grid.columns - 1, row: grid.rows - 1)
        let rect = try #require(grid.rect(of: last))
        #expect(rect == PixelRect(x: 17_920, y: 11_776, width: 80, height: 224))
        let tile = try Pixels(PageRenderer().renderTile(tree, scale: 60, tile: rect).image)
        #expect(tile.rgb(50, 190) == (255, 0, 0), "사각형 안")
        #expect(tile.rgb(10, 190) == (255, 255, 255), "사각형 왼쪽")
        #expect(tile.rgb(50, 100) == (255, 255, 255), "사각형 위쪽")
        // 사각형의 경계가 정확히 비트맵 17940 / 11940 에 있다.
        #expect(tile.rgb(19, 190) == (255, 255, 255) && tile.rgb(20, 190) == (255, 0, 0))
        #expect(tile.rgb(50, 163) == (255, 255, 255) && tile.rgb(50, 164) == (255, 0, 0))
    }

    @Test("비트맵을 벗어나거나 너무 큰 타일은 오류다")
    func invalidTiles() throws {
        let tree = try makeLeafTree(ops: [OpJSON.background()], width: 100, height: 100)
        let renderer = PageRenderer()
        for bad in [
            PixelRect(x: 60, y: 0, width: 50, height: 50), PixelRect(x: 0, y: 60, width: 50, height: 50),
            PixelRect(x: -1, y: 0, width: 50, height: 50), PixelRect(x: 0, y: 0, width: 0, height: 50),
        ] {
            #expect(throws: RenderError.invalidTile(bad)) { _ = try renderer.renderTile(tree, scale: 1, tile: bad) }
        }
        // 한 변 상한(4096px)을 넘는 타일.
        let wide = try makeLeafTree(ops: [], width: 9000, height: 10)
        let tooWide = PixelRect(x: 0, y: 0, width: 4097, height: 10)
        #expect(throws: RenderError.invalidTile(tooWide)) { _ = try renderer.renderTile(wide, scale: 1, tile: tooWide) }
    }
}

// MARK: - 해석적 기하와 큰 배율

/// 해석적 덮임과의 허용 오차. 부분 표본의 오차(±0.03)와, CoreGraphics가 선 끝 모서리의 작은 덮임(0.1 이하)을 8비트
/// 안티앨리어싱에서 버리는 차이(관측 0.082)를 합친 값이다. 가장자리가 0.1px만 어긋나도 그 가장자리 픽셀의 오차가 0.1이 된다.
private let analyticTolerance = 0.1

/// 선분(굵기 `2 × half`, 평평한 끝)이 픽셀 `(px, py)`를 덮는 비율. 16×16 부분 표본이라 ±0.03 정도의 표본 오차가 있다.
private func lineCoverage(from a: CGPoint, to b: CGPoint, half: Double, px: Int, py: Int) -> Double {
    var hits = 0
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    for i in 0..<16 {
        for j in 0..<16 {
            let x = Double(px) + (Double(i) + 0.5) / 16, y = Double(py) + (Double(j) + 0.5) / 16
            let t = ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared
            guard t >= 0, t <= 1 else { continue }
            let cx = a.x + t * dx, cy = a.y + t * dy
            if ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot() <= half { hits += 1 }
        }
    }
    return Double(hits) / 256
}

/// 흰 바탕에 검정 선분 하나를 그린 비트맵이 해석적 덮임에서 얼마나 벗어났는지. 선에서 먼 픽셀은 흰색이어야 한다(오차 = 잉크 양).
private func coverageError(of pixels: Pixels, line: (a: CGPoint, b: CGPoint, half: Double)) -> (max: Double, mean: Double, worst: String) {
    var maxError = 0.0, total = 0.0, counted = 0
    var worst = ""
    let dx = line.b.x - line.a.x, dy = line.b.y - line.a.y
    let lengthSquared = dx * dx + dy * dy
    for y in 0..<pixels.height {
        for x in 0..<pixels.width {
            // 픽셀 중심에서 선분까지의 거리로 선 근처인지 먼저 거른다(먼 픽셀의 표본 추출을 생략).
            let cx = Double(x) + 0.5, cy = Double(y) + 0.5
            let t = max(0, min(1, ((cx - line.a.x) * dx + (cy - line.a.y) * dy) / lengthSquared))
            let distance = ((cx - line.a.x - t * dx) * (cx - line.a.x - t * dx) + (cy - line.a.y - t * dy) * (cy - line.a.y - t * dy)).squareRoot()
            let ink = 1 - Double(pixels.rgb(x, y).r) / 255
            let expected = distance > line.half + 1.5 ? 0 : lineCoverage(from: line.a, to: line.b, half: line.half, px: x, py: y)
            let error = abs(ink - expected)
            if distance <= line.half + 1.5 { total += error; counted += 1 }
            if error > maxError { maxError = error; worst = "(\(x), \(y)) 잉크 \(ink) 해석 \(expected)" }
        }
    }
    return (maxError, counted > 0 ? total / Double(counted) : 0, worst)
}

@Suite("타일 합성 — 해석적 기하와 큰 배율")
struct TileAnalyticTests {
    private let diagonal = (a: CGPoint(x: 5, y: 5), b: CGPoint(x: 195, y: 135), width: 1.0)

    @Test("대각선의 덮임은 해석적 기하와 맞고, 어긋난 픽셀에서는 타일이 통째 렌더보다 정답에 가깝다", arguments: [(1.0, 64), (2.5, 64), (2.5, 37)])
    func diagonalLineMatchesAnalyticCoverage(scale: Double, tileSize: Int) throws {
        let tree = try makeLeafTree(ops: [Ops.background(), Ops.line(diagonal.a.x, diagonal.a.y, diagonal.b.x, diagonal.b.y, width: diagonal.width)], width: 200, height: 140)
        let scaledLine = (
            a: CGPoint(x: diagonal.a.x * scale, y: diagonal.a.y * scale), b: CGPoint(x: diagonal.b.x * scale, y: diagonal.b.y * scale),
            half: diagonal.width * scale / 2
        )
        let (composite, _) = try compose(tree, scale: scale, tileSize: tileSize)
        let full = try Pixels(PageRenderer().render(tree, scale: scale).image)
        let tiled = coverageError(of: composite, line: scaledLine)
        let whole = coverageError(of: full, line: scaledLine)
        #expect(tiled.max <= analyticTolerance, "타일: 최대 오차 \(tiled.max) \(tiled.worst)")
        // 같은 선에서 타일이 통째 렌더보다 정답에서 멀지 않다(선 근처 픽셀의 평균 오차).
        #expect(tiled.mean <= whole.mean + 0.001, "타일 평균 \(tiled.mean), 통째 평균 \(whole.mean)")
    }

    @Test("4096px를 넘는 배율(4200×560)에서도 타일 합성은 통째 렌더와 같고 긴 대각선은 해석적 기하와 맞는다")
    func beyondTheOldPixelCap() throws {
        // 300×40 쪽 @14배 = 4200×560. 옛 정책의 한 변 상한(4096px)을 넘는다.
        let scale = 14.0
        let exact = try makeLeafTree(ops: [
            Ops.background(width: 300, height: 40),
            Ops.rect(13.3, 4.1, 120, 20, fill: "#3366cc", stroke: "#000000", width: 0.4),
            Ops.line(10, 30, 290, 30, color: "#006600", width: 2, dash: "dash"),
            Ops.text("Tile", size: 18, originX: 150, baseline: 28, step: 11),
        ], width: 300, height: 40)
        let result = try compare(exact, scale: scale, tileSize: 512)
        #expect(result.tiles == 9 * 2)
        #expect(result.differing == 0, "\(result)")

        // 긴 대각선(길이 4200px 안팎). 통째 렌더는 이 크기에서 해석적 덮임에서 크게 벗어나지만(평균 오차 0.13) 타일은 맞는다.
        let slanted = try makeLeafTree(ops: [Ops.background(width: 300, height: 40), Ops.line(0, 0, 300, 40, width: 0.7)], width: 300, height: 40)
        let (composite, _) = try compose(slanted, scale: scale, tileSize: 512)
        let error = coverageError(of: composite, line: (CGPoint(x: 0, y: 0), CGPoint(x: 300 * scale, y: 40 * scale), 0.7 * scale / 2))
        #expect(error.max <= analyticTolerance, "최대 오차 \(error.max) \(error.worst)")
    }
}

// MARK: - 실제 문서

@Suite("타일 합성 vs 통째 렌더 — 실제 문서")
struct RealDocumentTileTests {
    fileprivate struct Case: Sendable, CustomTestStringConvertible {
        let file: String
        let page: Int
        let scale: Double
        let tileSize: Int
        var testDescription: String { "\(file) \(page + 1)쪽 @\(scale) 타일 \(tileSize)px" }
    }

    /// 글자·표·그림·수식·장식·탭 리더·양식·원본 SVG·그라데이션이 든 쪽(4단계 시험이 op를 확인한 쪽과 같다)과 타일 크기를
    /// 쪽 크기와 어긋나게 잡은 경우.
    private static let cases = [
        Case(file: "KTX.hwp", page: 0, scale: 1, tileSize: 256),
        Case(file: "KTX.hwp", page: 5, scale: 1.5, tileSize: 200),
        Case(file: "21868765_별표2_보건소_분장사무.hwp", page: 0, scale: 1, tileSize: 300),
        Case(file: "2025년 기부·답례품 실적 지자체 보고서_양식.hwpx", page: 3, scale: 1.25, tileSize: 256),
        Case(file: "hwp3-curve.hwp", page: 0, scale: 2, tileSize: 256),
        Case(file: "eq-01.hwp", page: 0, scale: 2, tileSize: 128),
        Case(file: "exam_math.hwp", page: 0, scale: 1.5, tileSize: 256),
        Case(file: "2022년 국립국어원 업무계획.hwp", page: 1, scale: 1, tileSize: 256),
        Case(file: "143E433F503322BD33.hwp", page: 0, scale: 1.5, tileSize: 256),
        Case(file: "bitmap.hwp", page: 0, scale: 1.5, tileSize: 256),
        Case(file: "form-01.hwp", page: 0, scale: 1, tileSize: 256),
        Case(file: "2010-01-06.hwp", page: 0, scale: 2, tileSize: 256),
    ]

    @Test("실제 쪽도 타일을 이어 붙이면 통째 렌더와 같은 모습이다(차이는 곡선·기울어진 변의 몇 단계뿐)", arguments: cases)
    fileprivate func tilesMatchTheWholePage(_ testCase: Case) async throws {
        let session = try await Fixtures.openSession(testCase.file)
        let tree = try await session.layerTree(page: testCase.page)
        let result = try compare(tree, scale: testCase.scale, tileSize: testCase.tileSize)
        #expect(result.tiles > 1, "한 장이면 경계 시험이 되지 않는다")
        // 관측: 최대 5단계(수식의 곡선), 대부분 0~1. 16은 위 `slantedEdgesStayWithinTolerance`와 같은 상한이다.
        // 타일이 1px만 어긋나도 글자 가장자리에서 100을 넘는 차이가 나므로 이 한도로 걸러진다.
        #expect(result.maxDelta <= 16, "\(testCase.testDescription): \(result)")
    }
}

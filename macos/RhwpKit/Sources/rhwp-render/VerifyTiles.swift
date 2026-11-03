import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender

/// 타일 경로를 샘플 전체에서 검증하는 `--verify-tiles` 모드.
///
/// 쪽마다 두 가지를 픽셀 단위로 대조한다.
///
/// 1. **걸러내기(`Culling`)**: `renderTile`이 그린 타일(보이는 영역 밖의 op를 건너뜀)과 같은 타일 컨텍스트에 **걸러내지 않고 전부 그린** 타일.
///    걸러내기는 결과를 바꾸지 않고 비용만 줄인다고 약속했고, 그 약속은 잎 op의 여백(24px)이 "엔진이 bbox 밖으로 그리는 양보다 크다"는 가정에 기댄다.
///    둘이 한 픽셀이라도 다르면 가정이 깨진 것이다. 이 비교가 가정의 직접 검사다(통째 렌더와의 비교는 컨텍스트 크기에서 오는 CoreGraphics의 반올림 차이가
///    섞여 걸러내기의 오류를 가린다).
/// 2. **타일 합성 대 통째 렌더**: 걸러낸 타일을 통째 렌더의 같은 영역과 견준다. 기울어진 변·곡선·그라데이션은 설계상 몇 단계 다를 수 있으므로
///    (architecture 문서 "타일 합성과 통째 렌더의 픽셀 비교") 차이의 크기 분포만 모은다.
///
/// 쪽 비트맵이 한 변 16384px를 넘으면 통째 렌더가 없으므로 2번은 건너뛰고 1번만 한다.
enum VerifyTiles {
    struct Totals {
        var pages = 0
        var tiles = 0
        var skippedWhole = 0
        /// 걸러낸 타일과 걸러내지 않은 타일이 다른 타일 수와 그 최대 채널 차이(0이어야 한다).
        var cullMismatchTiles = 0
        var cullMaxDiff = 0
        /// 걸러낸 타일 대 통째 렌더: 4단계(8비트) 넘게 다른 픽셀이 있는 타일 수, 최대 채널 차이.
        var wholeMismatchTiles = 0
        var wholeMaxDiff = 0
        /// 걸러내기로 건너뛴 op 비율을 가늠하려는 값(걸러낸 쪽·안 걸러낸 쪽의 그린 op 수 합).
        var culledOps = 0
        var fullOps = 0
    }

    static func run(document: URL, pages: PageSelection?, scale: Double, tileSize: Int) async throws {
        let session = try await RhwpDocumentSession.open(contentsOf: document)
        let total = try await session.pageCount()
        let renderer = PageRenderer()
        var totals = Totals()
        var details: [String] = []

        for number in 1...max(total, 1) where total > 0 && (pages?.contains(number) ?? true) {
            let tree = try await session.layerTree(page: number - 1)
            let grid = TileGrid(pageWidth: tree.pageWidth, pageHeight: tree.pageHeight, scale: scale, tileSize: tileSize)
            if grid.isEmpty { continue }
            totals.pages += 1

            // 통째 렌더(있으면). 쪽이 너무 크면 nil.
            var wholePixels: [UInt8]?
            if let whole = try? renderer.render(tree, scale: scale) {
                wholePixels = pixels(of: whole.image)
            } else {
                totals.skippedWhole += 1
            }

            for row in 0..<grid.rows {
                for column in 0..<grid.columns {
                    let index = TileIndex(column: column, row: row)
                    guard let rect = grid.rect(of: index) else { continue }
                    totals.tiles += 1

                    let culled = try renderer.renderTile(tree, scale: scale, tile: rect)
                    let culledPixels = pixels(of: culled.image)
                    let full = try drawUnculledTile(tree: tree, scale: scale, tile: rect, renderer: renderer)
                    totals.culledOps += culled.report.rendered.values.reduce(0, +)
                    totals.fullOps += full.report.rendered.values.reduce(0, +)
                    let fullPixels = pixels(of: full.image)

                    let cull = compare(culledPixels, fullPixels)
                    if cull.maxDiff > 0 {
                        totals.cullMismatchTiles += 1
                        totals.cullMaxDiff = max(totals.cullMaxDiff, cull.maxDiff)
                        // 다른 픽셀의 외접 사각형을 쪽 좌표(px)로 적는다: 어떤 op가 잘못 걸러졌는지 찾는 단서다.
                        let box = differenceBox(culledPixels, fullPixels, width: rect.width)
                        let pageBox = box.map {
                            String(format: "쪽 px x %.0f–%.0f, y %.0f–%.0f",
                                   Double(rect.x + $0.minX) / scale, Double(rect.x + $0.maxX + 1) / scale,
                                   Double(rect.y + $0.minY) / scale, Double(rect.y + $0.maxY + 1) / scale)
                        } ?? "?"
                        details.append("  걸러내기 불일치: \(number)쪽 타일(\(column),\(row)) 최대 \(cull.maxDiff), 다른 픽셀 \(cull.differing), \(pageBox)")
                        // 걸러낸 op 종류별 개수(걸러내지 않은 쪽 − 걸러낸 쪽): 불일치를 만든 op 종류의 단서.
                        let skipped = full.report.rendered.compactMap { key, count -> String? in
                            let diff = count - (culled.report.rendered[key] ?? 0)
                            return diff > 0 ? "\(key)×\(diff)" : nil
                        }.sorted().joined(separator: " ")
                        details.append("      걸러낸 op: \(skipped)")
                        if let box {
                            let at = (box.minY * rect.width + box.minX) * 4
                            details.append("      첫 다른 픽셀(타일 \(box.minX),\(box.minY)): 걸러냄 \(culledPixels[at..<(at + 4)].map { String($0) }.joined(separator: ",")) / 안 걸러냄 \(fullPixels[at..<(at + 4)].map { String($0) }.joined(separator: ","))")
                        }
                        if let box {
                            let area = CGRect(
                                x: Double(rect.x + box.minX) / scale, y: Double(rect.y + box.minY) / scale,
                                width: Double(box.maxX - box.minX + 1) / scale, height: Double(box.maxY - box.minY + 1) / scale
                            )
                            for line in candidates(near: area, in: tree).prefix(6) { details.append("      후보 op: " + line) }
                        }
                    }

                    if let wholePixels {
                        let crop = crop(wholePixels, pageWidth: grid.pixelWidth, rect: rect)
                        let whole = compare(culledPixels, crop)
                        if whole.maxDiff > 4 { totals.wholeMismatchTiles += 1 }
                        totals.wholeMaxDiff = max(totals.wholeMaxDiff, whole.maxDiff)
                    }
                }
            }
        }

        let name = document.lastPathComponent
        let ratio = totals.fullOps > 0 ? Double(totals.culledOps) / Double(totals.fullOps) * 100 : 100
        print("\(name)\t쪽 \(totals.pages)\t타일 \(totals.tiles)\t통째 생략 \(totals.skippedWhole)\t"
              + "걸러내기 불일치 \(totals.cullMismatchTiles) (최대 \(totals.cullMaxDiff))\t"
              + "통째와 4단계 넘게 다른 타일 \(totals.wholeMismatchTiles) (최대 \(totals.wholeMaxDiff))\t"
              + "그린 op 비율 \(String(format: "%.0f", ratio))%")
        for line in details.prefix(20) { print(line) }
    }

    /// 다른 픽셀 영역 근처(40px 안)에 bbox가 닿는 잎 op들의 설명. 어떤 op의 범위 계산이 틀렸는지 찾는 단서다.
    private static func candidates(near area: CGRect, in tree: PageLayerTree) -> [String] {
        var found: [String] = []
        func describe(_ op: PaintOp) -> (String, CGRect)? {
            switch op {
            case let .line(o): return ("line 굵기 \(o.style.width)", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .rectangle(o): return ("rectangle 선 \(o.style.strokeWidth)", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .ellipse(o): return ("ellipse", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .path(o): return ("path", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .image(o): return ("image", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .textRun(o): return ("textRun", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .textDecoration(o): return ("textDecoration", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .tabLeader(o): return ("tabLeader", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .rawSvg(o): return ("rawSvg", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            case let .equation(o): return ("equation", CGRect(x: o.bbox.x, y: o.bbox.y, width: o.bbox.width, height: o.bbox.height))
            default: return nil
            }
        }
        func walk(_ node: LayerNode) {
            switch node.content {
            case let .group(_, children): children.forEach(walk)
            case let .clip(_, _, child): walk(child)
            case let .leaf(ops):
                for op in ops {
                    guard let (name, box) = describe(op), box.insetBy(dx: -40, dy: -40).intersects(area) else { continue }
                    found.append(String(format: "%@ bbox (%.1f, %.1f, %.1f×%.1f)", name, box.minX, box.minY, box.width, box.height))
                }
            case .unsupported: break
            }
        }
        walk(tree.root)
        return found
    }

    /// 걸러내지 않고 전부 그린 타일. `PageRenderer.renderTile`과 같은 컨텍스트·변환이다(걸러내기만 뺀다).
    private static func drawUnculledTile(
        tree: PageLayerTree, scale: Double, tile: PixelRect, renderer: PageRenderer
    ) throws -> (image: CGImage, report: RenderReport) {
        guard let context = makeContext(width: tile.width, height: tile.height) else { throw RenderError.bitmapUnavailable }
        context.translateBy(x: -CGFloat(tile.x), y: CGFloat(tile.height + tile.y))
        context.scaleBy(x: scale, y: -scale)
        let report = renderer.draw(tree, into: context)
        guard let image = context.makeImage() else { throw RenderError.bitmapUnavailable }
        return (image, report)
    }

    /// `PageRenderer`가 쓰는 것과 같은 비트맵 형식(sRGB, 8비트, 곱해진 알파).
    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// 이미지의 RGBA 바이트(행마다 `width × 4`, 빈틈 없음). 비트맵 컨텍스트가 만든 이미지를 같은 형식의 컨텍스트에 그대로 옮겨 얻는다.
    private static func pixels(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            if let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                context.setBlendMode(.copy)
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        return bytes
    }

    private static func crop(_ page: [UInt8], pageWidth: Int, rect: PixelRect) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: rect.width * rect.height * 4)
        for y in 0..<rect.height {
            let source = ((rect.y + y) * pageWidth + rect.x) * 4
            let target = y * rect.width * 4
            out.replaceSubrange(target..<(target + rect.width * 4), with: page[source..<(source + rect.width * 4)])
        }
        return out
    }

    /// 다른 픽셀의 외접 사각형(타일 좌표).
    private static func differenceBox(_ a: [UInt8], _ b: [UInt8], width: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        guard a.count == b.count, width > 0 else { return nil }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for i in stride(from: 0, to: a.count, by: 4) where a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] || a[i + 3] != b[i + 3] {
            let pixel = i / 4
            let x = pixel % width, y = pixel / width
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        return maxX >= 0 ? (minX, minY, maxX, maxY) : nil
    }

    private static func compare(_ a: [UInt8], _ b: [UInt8]) -> (maxDiff: Int, differing: Int) {
        guard a.count == b.count else { return (255, max(a.count, b.count)) }
        var maxDiff = 0
        var differing = 0
        for i in 0..<a.count where a[i] != b[i] {
            maxDiff = max(maxDiff, abs(Int(a[i]) - Int(b[i])))
            differing += 1
        }
        return (maxDiff, differing)
    }
}

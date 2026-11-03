import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender

/// 뷰어의 타일 크기·여유·동시 시작 수를 측정으로 고르기 위한 `--tile-tune` 모드.
///
/// 뷰어가 한 화면을 채우는 일을 흉내 낸다: 쪽 비트맵 위의 **보이는 영역**(창 크기 × 배율)에 여유(타일 수의 몇 배)를 더해 겹치는 타일을 구하고,
/// 동시에 `concurrency`장씩 그려 전부 끝날 때까지의 **벽시계 시간**(화면이 다 차는 시간)과 **일한 시간의 합**(CPU 비용)을 잰다. 레이어 트리 디코딩은 쪽당
/// 한 번이고 캐시되므로(뷰어의 설계) 재지 않는다. 보이는 영역은 쪽 위·가운데·아래 세 자리에서 잰다.
///
/// 출력은 한 줄에 한 측정(TSV)이고 집계는 호출한 쪽(스크립트)이 한다. 반드시 릴리스 빌드로 잰다.
enum TileTune {
    /// Retina 화면 배율. 뷰어의 `scale`은 확대 × 이 값이다.
    static let screenScale = 2.0

    static func run(
        document: URL, pages: PageSelection?, scale: Double,
        tileSizes: [Int], margins: [Double], concurrencies: [Int], viewport: (width: Double, height: Double)
    ) async throws {
        let session = try await RhwpDocumentSession.open(contentsOf: document)
        let total = try await session.pageCount()
        let renderer = PageRenderer()
        let clock = ContinuousClock()
        let name = document.lastPathComponent

        for number in 1...max(total, 1) where total > 0 && (pages?.contains(number) ?? true) {
            let tree = try await session.layerTree(page: number - 1)
            for tileSize in tileSizes {
                let grid = TileGrid(pageWidth: tree.pageWidth, pageHeight: tree.pageHeight, scale: scale, tileSize: tileSize)
                if grid.isEmpty { continue }
                // 보이는 영역은 **장치 픽셀**로 일정하다(창 크기 × 화면 배율 2). 확대(`scale` = 확대 × 2)해도 화면에 들어오는 비트맵 면적은 그대로이고
                // 쪽이 커져 일부만 보일 뿐이다.
                let viewWidth = viewport.width * Self.screenScale
                let viewHeight = viewport.height * Self.screenScale
                // 보이는 영역을 쪽 위·가운데·아래에 둔다(쪽이 화면보다 작으면 한 자리).
                let maxY = max(Double(grid.pixelHeight) - viewHeight, 0)
                let offsets: [Double] = maxY > 0 ? [0, maxY / 2, maxY] : [0]
                for offsetY in offsets {
                    for margin in margins {
                        // 여유: 보이는 영역 둘레에 타일 `margin`장만큼 더한다.
                        let pad = margin * Double(tileSize)
                        let region = CGRect(
                            x: -pad, y: offsetY - pad,
                            width: min(viewWidth, Double(grid.pixelWidth)) + 2 * pad, height: viewHeight + 2 * pad
                        )
                        let indices = grid.tiles(intersecting: region)
                        if indices.isEmpty { continue }
                        for concurrency in concurrencies {
                            let started = clock.now
                            let work = await drawAll(indices, grid: grid, tree: tree, scale: scale, renderer: renderer, concurrency: concurrency)
                            let wall = clock.now - started
                            print([
                                name, String(number), String(tileSize), String(margin), String(concurrency),
                                String(format: "%.0f", offsetY), String(indices.count),
                                String(format: "%.2f", Bench.milliseconds(wall)), String(format: "%.2f", work),
                                String(grid.pixelWidth), String(grid.pixelHeight),
                            ].joined(separator: "\t"))
                        }
                    }
                }
            }
        }
    }

    /// 타일을 `concurrency`장씩 동시에 그리고 개별 시간의 합(ms)을 돌려준다.
    private static func drawAll(
        _ indices: [TileIndex], grid: TileGrid, tree: PageLayerTree, scale: Double,
        renderer: PageRenderer, concurrency: Int
    ) async -> Double {
        await withTaskGroup(of: Double.self) { group in
            var iterator = indices.makeIterator()
            var running = 0
            var sum = 0.0
            func start(_ index: TileIndex) {
                group.addTask {
                    let clock = ContinuousClock()
                    let begin = clock.now
                    if let rect = grid.rect(of: index) { _ = try? renderer.renderTile(tree, scale: scale, tile: rect) }
                    return Bench.milliseconds(clock.now - begin)
                }
            }
            while running < concurrency, let next = iterator.next() {
                start(next)
                running += 1
            }
            while let finished = await group.next() {
                sum += finished
                if let next = iterator.next() { start(next) }
            }
            return sum
        }
    }
}

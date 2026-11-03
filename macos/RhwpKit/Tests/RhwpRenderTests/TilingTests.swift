import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender
import Testing

// 타일 격자의 기하. 타일을 그려 통째 렌더와 견주는 시험은 `TileRenderTests.swift`에 있다.

@Suite("TileGrid — 격자 기하")
struct TileGridTests {
    @Test("격자는 통째 렌더의 비트맵 크기를 올림해 덮고 가장자리 타일만 작다")
    func gridCoversTheBitmapWithoutGaps() throws {
        // 100×60 쪽을 2.5배 → 250×150px. 64px 타일이면 가로 4칸(64·3+58), 세로 3칸(64·2+22).
        let grid = TileGrid(pageWidth: 100, pageHeight: 60, scale: 2.5, tileSize: 64)
        #expect((grid.pixelWidth, grid.pixelHeight) == (250, 150))
        #expect((grid.columns, grid.rows) == (4, 3))
        #expect(grid.rect(of: TileIndex(column: 0, row: 0)) == PixelRect(x: 0, y: 0, width: 64, height: 64))
        #expect(grid.rect(of: TileIndex(column: 3, row: 0)) == PixelRect(x: 192, y: 0, width: 58, height: 64))
        #expect(grid.rect(of: TileIndex(column: 3, row: 2)) == PixelRect(x: 192, y: 128, width: 58, height: 22))
        // 모든 타일의 넓이 합이 비트맵 넓이와 같다(빈틈도 겹침도 없다).
        var area = 0
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let rect = try #require(grid.rect(of: TileIndex(column: column, row: row)))
                area += rect.width * rect.height
            }
        }
        #expect(area == 250 * 150)
    }

    @Test("비트맵 크기는 소수 픽셀을 올린다")
    func fractionalPixelsRoundUp() {
        // 793.7×1122.5 px 쪽 @2배 = 1587.4×2245 → 1588×2245.
        let grid = TileGrid(pageWidth: 793.7, pageHeight: 1122.5, scale: 2)
        #expect((grid.pixelWidth, grid.pixelHeight) == (1588, 2245))
    }

    @Test("격자 밖 번호는 사각형이 없다")
    func outOfRangeIndex() {
        let grid = TileGrid(pageWidth: 100, pageHeight: 100, scale: 1, tileSize: 64)
        #expect(grid.rect(of: TileIndex(column: 2, row: 0)) == nil)
        #expect(grid.rect(of: TileIndex(column: 0, row: -1)) == nil)
    }

    @Test("영역과 겹치는 타일만 고른다: 경계에 닿기만 하면 빼고, 걸치면 넣는다")
    func tilesIntersectingARegion() {
        let grid = TileGrid(pageWidth: 400, pageHeight: 400, scale: 1, tileSize: 100)
        // 정확히 한 칸.
        #expect(grid.tiles(intersecting: CGRect(x: 100, y: 100, width: 100, height: 100)) == [TileIndex(column: 1, row: 1)])
        // 1px 걸치면 이웃 칸이 들어온다.
        let spill = grid.tiles(intersecting: CGRect(x: 100, y: 100, width: 101, height: 100))
        #expect(spill == [TileIndex(column: 1, row: 1), TileIndex(column: 2, row: 1)])
        // 위→아래, 왼쪽→오른쪽 순서.
        let block = grid.tiles(intersecting: CGRect(x: 50, y: 50, width: 100, height: 100))
        #expect(block == [
            TileIndex(column: 0, row: 0), TileIndex(column: 1, row: 0),
            TileIndex(column: 0, row: 1), TileIndex(column: 1, row: 1),
        ])
    }

    @Test("비트맵 밖으로 넘치는 영역은 안쪽만 센다. 완전히 밖이거나 비정상이면 비어 있다")
    func regionsOutsideTheBitmap() {
        let grid = TileGrid(pageWidth: 250, pageHeight: 150, scale: 1, tileSize: 100)
        #expect(grid.tiles(intersecting: CGRect(x: -500, y: -500, width: 5000, height: 5000)).count == grid.tileCount)
        #expect(grid.tiles(intersecting: CGRect(x: 300, y: 0, width: 50, height: 50)).isEmpty)
        #expect(grid.tiles(intersecting: CGRect(x: -100, y: 0, width: 100, height: 50)).isEmpty, "닿기만 하는 왼쪽 밖")
        #expect(grid.tiles(intersecting: CGRect(x: 0, y: 0, width: 0, height: 50)).isEmpty, "넓이가 없는 영역")
        #expect(grid.tiles(intersecting: CGRect(x: Double.nan, y: 0, width: 50, height: 50)).isEmpty)
    }

    @Test("비정상 쪽 크기와 상한을 넘는 비트맵은 빈 격자다", arguments: [
        (0.0, 100.0, 1.0), (100.0, -1.0, 1.0), (.nan, 100.0, 1.0), (100.0, 100.0, 0.0), (100.0, 100.0, .infinity),
        (1000.0, 1000.0, 40.0),
    ])
    func degenerateGrids(width: Double, height: Double, scale: Double) {
        #expect(TileGrid(pageWidth: width, pageHeight: height, scale: scale).isEmpty)
    }

    @Test("4096px를 넘는 배율도 격자로 나뉜다")
    func gridBeyondTheOldCap() {
        // 쪽 하나가 한 변 4096px를 넘던 크기(A4 @ 8배 = 6350×8980)를 512px 타일로 나눈다.
        let grid = TileGrid(pageWidth: 793.7, pageHeight: 1122.5, scale: 8, tileSize: 512)
        #expect(grid.pixelWidth > 4096 && grid.pixelHeight > 4096)
        #expect((grid.columns, grid.rows) == (13, 18))
        // 기본 타일(1024px)이면 7열 × 9행이다.
        let measured = TileGrid(pageWidth: 793.7, pageHeight: 1122.5, scale: 8)
        #expect((measured.columns, measured.rows) == (7, 9))
    }

    @Test("타일이 덮는 쪽 영역은 비트맵 좌표를 배율로 나눈 값이다")
    func pageRectOfATile() throws {
        let grid = TileGrid(pageWidth: 100, pageHeight: 60, scale: 2.5, tileSize: 64)
        let rect = try #require(grid.pageRect(of: TileIndex(column: 1, row: 1), scale: 2.5))
        #expect(rect == CGRect(x: 25.6, y: 25.6, width: 25.6, height: 25.6))
    }
}

import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender

/// 쪽 하나에서 지금 화면에 필요한 타일을 고른 결과.
public struct TilePlan: Sendable, Equatable {
    /// 이 쪽을 그리는 px→비트맵 배율(캐시 키와 같은 1/1000 반올림 값).
    public let scale: Double
    /// 그 배율에서 쪽 비트맵을 나눈 격자.
    public let grid: TileGrid
    /// 필요한 타일. 보이는 영역의 중심에 가까운 것부터다(먼저 그릴수록 사용자가 먼저 본다).
    public let tiles: [TileIndex]

    /// 타일이 쪽 프레임 안에서 차지하는 사각형(pt, 원점은 쪽 왼쪽 위). 격자 밖 번호면 nil.
    ///
    /// 비트맵 픽셀 → 화면 pt 환산은 `zoom / scale`이다. 배율이 `zoom × 화면 배율`이면 1/화면 배율이라 타일 경계가 장치
    /// 픽셀에 정확히 놓이고, 상한 때문에 배율이 낮아졌을 때만 소수가 된다.
    public func frame(of tile: TileIndex, zoom: Double) -> CGRect? {
        guard let rect = grid.rect(of: tile), scale > 0 else { return nil }
        let k = zoom / scale
        return CGRect(x: Double(rect.x) * k, y: Double(rect.y) * k, width: Double(rect.width) * k, height: Double(rect.height) * k)
    }
}

public enum TilePlanner {
    /// 쪽 `frame`(스크롤 내용 좌표)이 `visible`(스크롤 내용 좌표의 보이는 영역)과 겹치는 부분을 덮는 타일을 고른다.
    ///
    /// `overscan`은 보이는 영역을 사방으로 넓혀 미리 그릴 타일 수(타일 한 변 단위)다. 스크롤하면 곧 보일 곳을 미리 채워
    /// 빈 타일이 눈에 띄지 않게 한다. 쪽이 보이는 영역과 겹치지 않으면 타일이 없다.
    public static func plan(
        pageSize: PageSize, frame: PageFrame, zoom: Zoom, scale: Double, visible: CGRect,
        tileSize: Int = TileGrid.defaultTileSize, overscan: Double = 0.5
    ) -> TilePlan {
        let grid = TileGrid(pageWidth: pageSize.width, pageHeight: pageSize.height, scale: scale, tileSize: tileSize)
        guard !grid.isEmpty, zoom.factor > 0 else { return TilePlan(scale: scale, grid: grid, tiles: []) }

        // 내용 좌표 → 쪽 안 pt → 비트맵 px.
        let k = scale / zoom.factor
        let region = CGRect(
            x: (visible.minX - frame.x) * k, y: (visible.minY - frame.y) * k,
            width: visible.width * k, height: visible.height * k
        )
        let margin = overscan * Double(grid.tileSize)
        let wanted = region.insetBy(dx: -margin, dy: -margin)
        let tiles = grid.tiles(intersecting: wanted)

        // 보이는 영역의 중심에 가까운 순서. 중심은 비트맵 좌표다.
        let center = CGPoint(x: region.midX, y: region.midY)
        func distance(_ tile: TileIndex) -> Double {
            guard let rect = grid.rect(of: tile) else { return .infinity }
            let dx = Double(rect.x) + Double(rect.width) / 2 - center.x
            let dy = Double(rect.y) + Double(rect.height) / 2 - center.y
            return dx * dx + dy * dy
        }
        let ordered = tiles.sorted { (distance($0), $0) < (distance($1), $1) }
        return TilePlan(scale: scale, grid: grid, tiles: ordered)
    }
}

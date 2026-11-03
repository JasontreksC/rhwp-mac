import CoreGraphics
import Foundation

/// 쪽 비트맵 위의 정수 픽셀 사각형. 원점은 비트맵 왼쪽 위, y는 아래로 늘어난다.
public struct PixelRect: Sendable, Hashable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
}

/// 타일 하나의 번호. 쪽 비트맵 왼쪽 위 타일이 (0, 0)이다.
public struct TileIndex: Sendable, Hashable, Comparable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// 위에서 아래, 왼쪽에서 오른쪽 순서. 정렬에 쓴다.
    public static func < (a: TileIndex, b: TileIndex) -> Bool {
        (a.row, a.column) < (b.row, b.column)
    }
}

/// 쪽 하나의 비트맵(배율을 적용한 크기)을 정사각 타일로 나눈 격자.
///
/// 비트맵 크기는 `PageRenderer.render(_:scale:)`가 만드는 비트맵과 **정확히 같다**(올림한 정수 픽셀). 타일은
/// 그 비트맵을 빈틈·겹침 없이 덮고, 오른쪽·아래 가장자리 타일만 남는 만큼 작다. 그래서 타일을 이어 붙이면
/// 쪽을 통째로 그린 비트맵이 되어야 한다(시험이 픽셀 단위로 지킨다).
public struct TileGrid: Sendable, Equatable {
    /// 타일 한 변의 기본 크기(px). 뷰어가 쓰는 값이다.
    ///
    /// 크면 타일 경계를 가로지르는 op를 두 번 그리는 낭비와 트리 순회 반복이 줄고, 작으면 한 장의 지연과
    /// 메모리가 줄어든다. 512px는 비트맵 한 장이 1MB(RGBA)라 LRU 비용 단위로도 알맞다.
    public static let defaultTileSize = 512

    /// 비트맵 한 변의 상한(px). 이 이상은 격자를 만들지 않는다(`isEmpty`).
    /// CoreGraphics는 좌표를 Float32로 래스터하므로 2^15px를 넘으면 1/512px보다 거칠어져 안티앨리어싱이 흔들린다.
    public static let maxPixelDimension = 32_768

    public let pixelWidth: Int
    public let pixelHeight: Int
    public let tileSize: Int
    public let columns: Int
    public let rows: Int

    /// 쪽 크기(px, 96dpi)와 px→비트맵 배율에서 격자를 만든다. 크기가 비정상(0 이하, NaN, 상한 초과)이면 빈 격자다.
    public init(pageWidth: Double, pageHeight: Double, scale: Double, tileSize: Int = TileGrid.defaultTileSize) {
        self.tileSize = max(tileSize, 1)
        let width = pageWidth * scale
        let height = pageHeight * scale
        guard width >= 1, height >= 1,
              width <= Double(Self.maxPixelDimension), height <= Double(Self.maxPixelDimension)
        else {
            pixelWidth = 0
            pixelHeight = 0
            columns = 0
            rows = 0
            return
        }
        pixelWidth = Int(width.rounded(.up))
        pixelHeight = Int(height.rounded(.up))
        columns = (pixelWidth + self.tileSize - 1) / self.tileSize
        rows = (pixelHeight + self.tileSize - 1) / self.tileSize
    }

    public var isEmpty: Bool { columns == 0 || rows == 0 }
    public var tileCount: Int { columns * rows }

    /// 타일의 비트맵 안 위치와 크기. 번호가 격자 밖이면 nil.
    public func rect(of index: TileIndex) -> PixelRect? {
        guard index.column >= 0, index.column < columns, index.row >= 0, index.row < rows else { return nil }
        let x = index.column * tileSize
        let y = index.row * tileSize
        return PixelRect(x: x, y: y, width: min(tileSize, pixelWidth - x), height: min(tileSize, pixelHeight - y))
    }

    /// 비트맵 좌표(px)의 사각형 `region`과 겹치는 타일들. 위→아래, 왼쪽→오른쪽 순서다.
    ///
    /// 경계가 정확히 닿기만 하는 타일은 포함하지 않는다(그 타일에는 `region`의 픽셀이 없다). `region`이 비트맵
    /// 밖으로 넘치면 비트맵 안쪽만 센다.
    public func tiles(intersecting region: CGRect) -> [TileIndex] {
        guard !isEmpty, region.width > 0, region.height > 0,
              region.minX.isFinite, region.maxX.isFinite, region.minY.isFinite, region.maxY.isFinite
        else { return [] }
        let size = Double(tileSize)
        // minX/minY 는 그 칸을 포함하고, maxX/maxY 는 정확히 경계에 닿으면 앞 칸까지만 센다(반열린 구간).
        let firstColumn = max(Int((region.minX / size).rounded(.down)), 0)
        let lastColumn = min(Int((region.maxX / size).rounded(.up)) - 1, columns - 1)
        let firstRow = max(Int((region.minY / size).rounded(.down)), 0)
        let lastRow = min(Int((region.maxY / size).rounded(.up)) - 1, rows - 1)
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return [] }
        var result: [TileIndex] = []
        result.reserveCapacity((lastColumn - firstColumn + 1) * (lastRow - firstRow + 1))
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                result.append(TileIndex(column: column, row: row))
            }
        }
        return result
    }

    /// 타일이 쪽 좌표(px)에서 덮는 사각형. 렌더링할 때 그리기 범위를 좁히는 데 쓴다.
    public func pageRect(of index: TileIndex, scale: Double) -> CGRect? {
        guard let rect = rect(of: index), scale > 0 else { return nil }
        return CGRect(
            x: Double(rect.x) / scale, y: Double(rect.y) / scale,
            width: Double(rect.width) / scale, height: Double(rect.height) / scale
        )
    }
}

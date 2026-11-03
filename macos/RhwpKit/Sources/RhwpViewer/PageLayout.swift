import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender

/// 쪽이 화면에서 차지하는 사각형(pt). 원점은 스크롤 내용의 왼쪽 위다.
public struct PageFrame: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxY: Double { y + height }
}

/// 쪽을 세로로 쌓은 스크롤 내용의 배치.
///
/// 모든 쪽의 크기를 미리 알고(`RhwpDocumentSession.pageSizes()`) 쪽 그림을 받기 전에 자리를 잡는다.
/// 그래서 그림이 늦게 도착해도 스크롤 길이가 흔들리지 않는다. 쪽은 가장 넓은 쪽을 기준으로 가운데 정렬한다.
/// 배치는 값이라 배율이 바뀌면 새로 만든다.
public struct PageLayout: Sendable, Equatable {
    /// 쪽 사이 간격(pt).
    public let spacing: Double
    /// 스크롤 내용 가장자리 여백(pt).
    public let margin: Double
    public let zoom: Zoom
    public let frames: [PageFrame]
    /// 스크롤 내용의 크기(pt).
    public let contentWidth: Double
    public let contentHeight: Double

    public init(pageSizes: [PageSize], zoom: Zoom, spacing: Double = 16, margin: Double = 24) {
        self.zoom = zoom
        self.spacing = spacing
        self.margin = margin

        let scale = zoom.factor
        let widest = pageSizes.map(\.width).max() ?? 0
        var y = margin
        var frames: [PageFrame] = []
        frames.reserveCapacity(pageSizes.count)
        for size in pageSizes {
            let width = size.width * scale
            let height = size.height * scale
            let x = margin + (widest * scale - width) / 2
            frames.append(PageFrame(x: x, y: y, width: width, height: height))
            y += height + spacing
        }
        self.frames = frames
        contentWidth = widest * scale + 2 * margin
        // 마지막 쪽 아래에는 간격이 아니라 가장자리 여백만 둔다.
        contentHeight = pageSizes.isEmpty ? 2 * margin : y - spacing + margin
    }

    public var pageCount: Int { frames.count }

    /// 세로 위치 `y`(스크롤 내용 좌표)에 가장 가까운 쪽. 쪽 사이 간격이나 가장자리에서는 가까운 쪽을 고른다.
    /// 쪽이 없으면 nil.
    public func pageIndex(atY y: Double) -> Int? {
        guard !frames.isEmpty else { return nil }
        // 첫 번째로 아래 끝(maxY)이 y 이후인 쪽을 이분 탐색으로 찾는다.
        var low = 0
        var high = frames.count - 1
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].maxY < y { low = mid + 1 } else { high = mid }
        }
        // 간격 안이면 앞 쪽과 이 쪽 중 가까운 쪽.
        if low > 0, y < frames[low].y, y - frames[low - 1].maxY < frames[low].y - y { return low - 1 }
        return low
    }

    /// 보이는 세로 구간 `[top, bottom]`과 조금이라도 겹치는 쪽들. `overscan`은 위아래로 더 넓혀 미리 그릴 거리(pt)다.
    public func visiblePages(top: Double, bottom: Double, overscan: Double = 0) -> Range<Int> {
        guard !frames.isEmpty, bottom >= top else { return 0..<0 }
        let lo = top - overscan
        let hi = bottom + overscan
        // 아래 끝이 lo 이상인 첫 쪽부터, 위 끝이 hi 이하인 마지막 쪽까지.
        guard let first = frames.firstIndex(where: { $0.maxY >= lo }),
              let last = frames.lastIndex(where: { $0.y <= hi }),
              first <= last
        else { return 0..<0 }
        return first..<(last + 1)
    }

    /// 쪽의 위쪽 가장자리로 스크롤할 내용 y. 쪽 번호가 범위 밖이면 nil.
    public func scrollOffset(forPage index: Int) -> Double? {
        frames.indices.contains(index) ? frames[index].y - margin : nil
    }

    /// 보이는 영역의 맨 위에 걸린 쪽. 위쪽 여백을 건너뛴 곳(`offsetY + margin`)을 기준으로 삼아서, `scrollOffset(forPage:)`로
    /// 스크롤한 직후(쪽의 위 가장자리가 정확히 이 선에 놓인다)에 그 쪽이 고른다. 쪽이 없으면 nil.
    public func topVisiblePage(offsetY: Double) -> Int? {
        pageIndex(atY: offsetY + margin)
    }

    /// 이전 배치 `old`에서 `point`(스크롤 내용 좌표, pt)가 가리키던 내용 위치를 이 배치에서 돌려준다.
    ///
    /// 확대·축소해도 사용자가 붙잡고 있던 곳(손가락 아래, 화면 중앙)이 같은 내용에 머물게 하려는 것이다. 쪽 안의 점은 쪽
    /// 프레임 안의 비율로 옮기고, 쪽 위·아래의 간격과 여백은 배율과 무관한 고정 길이이므로 가장 가까운 쪽 가장자리에서의
    /// 거리를 그대로 둔다. 가로는 모든 쪽이 같은 중심선을 쓰고 가장자리 여백만 고정이라 여백 안쪽을 배율 비로 옮긴다.
    /// 두 배치의 쪽수가 다르면(다른 문서) 단순 배율 비로 옮긴다.
    public func point(matching point: CGPoint, in old: PageLayout) -> CGPoint {
        let ratio = old.zoom.factor > 0 ? zoom.factor / old.zoom.factor : 1
        let x = margin + (point.x - old.margin) * ratio
        guard frames.count == old.frames.count, let index = old.pageIndex(atY: point.y) else {
            return CGPoint(x: x, y: point.y * ratio)
        }
        let before = old.frames[index]
        let after = frames[index]
        let y: Double
        if point.y < before.y {
            y = after.y - (before.y - point.y)
        } else if point.y > before.maxY {
            y = after.maxY + (point.y - before.maxY)
        } else if before.height > 0 {
            y = after.y + (point.y - before.y) / before.height * after.height
        } else {
            y = after.y
        }
        return CGPoint(x: x, y: y)
    }

    /// 보이는 영역의 크기가 `viewport`일 때 스크롤할 수 있는 가장 큰 왼쪽 위 위치.
    public func maxScrollOffset(for viewport: CGSize) -> CGPoint {
        CGPoint(x: max(0, contentWidth - viewport.width), y: max(0, contentHeight - viewport.height))
    }
}

/// 화면에 그릴 비트맵의 배율 정책.
public enum RenderScalePolicy {
    /// 쪽 비트맵 한 변의 상한(px). 쪽을 타일로 나눠 그리므로 메모리가 아니라 좌표 정밀도가 정한다(`TileGrid.maxPixelDimension`).
    /// 옛 정책은 쪽 하나를 통째로 그려서 4096px로 막았고 그 때문에 큰 배율에서 흐렸다.
    public static let maxPixelDimension = Double(TileGrid.maxPixelDimension)

    /// 화면에서 `zoom`으로 보이는 쪽을 선명하게 그릴 px→비트맵 배율.
    /// 기본은 `zoom × 화면 배율(Retina 2)`이고, 상한을 넘으면 상한에 맞춰 낮춘다.
    public static func scale(zoom: Zoom, displayScale: Double, pageSize: PageSize) -> Double {
        let wanted = zoom.factor * max(displayScale, 1)
        let longest = max(pageSize.width, pageSize.height)
        guard longest > 0 else { return wanted }
        return min(wanted, maxPixelDimension / longest)
    }

    /// 쪽 전체를 한 장으로 먼저 그려 두는 흐린 밑그림의 긴 변(px). 타일이 오기 전과 확대 배율이 바뀐 직후에 보여 준다.
    public static let coverLongSide: Double = 1024

    /// 밑그림의 배율. 쪽이 작아도 1을 넘기지 않는다(밑그림을 위해 더 정밀하게 그릴 이유가 없다).
    public static func coverScale(pageSize: PageSize) -> Double {
        let longest = max(pageSize.width, pageSize.height)
        guard longest > 0 else { return 1 }
        return min(1, coverLongSide / longest)
    }
}

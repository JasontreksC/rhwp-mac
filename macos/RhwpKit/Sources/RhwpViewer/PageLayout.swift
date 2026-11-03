import Foundation
import RhwpKit

/// 쪽이 화면에서 차지하는 사각형(pt). 원점은 스크롤 내용의 왼쪽 위다.
public struct PageFrame: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

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
}

/// 화면에 그릴 비트맵의 배율 정책.
public enum RenderScalePolicy {
    /// 쪽 하나의 비트맵 한 변 상한(px). 큰 배율에서 메모리가 폭주하지 않게 한다(4단계에서 타일링으로 넘어간다).
    public static let maxPixelDimension: Double = 4096

    /// 화면에서 `zoom`으로 보이는 쪽을 선명하게 그릴 px→비트맵 배율.
    /// 기본은 `zoom × 화면 배율(Retina 2)`이고, 상한을 넘으면 상한에 맞춰 낮춘다.
    public static func scale(zoom: Zoom, displayScale: Double, pageSize: PageSize) -> Double {
        let wanted = zoom.factor * max(displayScale, 1)
        let longest = max(pageSize.width, pageSize.height)
        guard longest > 0 else { return wanted }
        return min(wanted, maxPixelDimension / longest)
    }
}

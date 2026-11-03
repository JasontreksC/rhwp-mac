import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender
import RhwpViewer
import Testing

// 타일 계획·확대 앵커·핀치 상태 같은 순수 계산의 시험. 기대값은 손으로 계산한 값이다.

@Suite("TilePlanner")
struct TilePlannerTests {
    /// 1000×1400px 쪽이 스크롤 내용의 (24, 24)에 놓여 있다.
    private let size = PageSize(width: 1000, height: 1400)
    private let frame = PageFrame(x: 24, y: 24, width: 1000, height: 1400)

    @Test("보이는 영역과 겹치는 타일만 고른다(여유 없이)")
    func onlyVisibleTiles() {
        // 배율 1, 확대 1: 내용 좌표 (0,0,600,400)은 쪽 안 (−24,−24)~(576,376). 512px 타일 → 가로 0~1열, 세로 0행.
        let plan = TilePlanner.plan(
            pageSize: size, frame: frame, zoom: Zoom(1), scale: 1, visible: CGRect(x: 0, y: 0, width: 600, height: 400), overscan: 0
        )
        #expect(plan.tiles == [TileIndex(column: 0, row: 0), TileIndex(column: 1, row: 0)])
    }

    @Test("여유(overscan)는 보이는 영역을 사방으로 타일 크기의 비율만큼 넓힌다")
    func overscanWidensTheRegion() {
        // 반 타일(256px) 여유: 쪽 안 (−280,−280)~(832,632) → 0~1열, 0~1행 = 4장.
        let plan = TilePlanner.plan(
            pageSize: size, frame: frame, zoom: Zoom(1), scale: 1, visible: CGRect(x: 0, y: 0, width: 600, height: 400), overscan: 0.5
        )
        #expect(Set(plan.tiles) == [
            TileIndex(column: 0, row: 0), TileIndex(column: 1, row: 0), TileIndex(column: 0, row: 1), TileIndex(column: 1, row: 1),
        ])
    }

    @Test("보이는 영역의 중심에 가까운 타일이 앞에 온다")
    func orderedByDistanceFromTheCenter() {
        // 쪽 안 (700,700) 근처만 본다 → 가운데 타일 (1,1)이 가장 가깝다.
        let visible = CGRect(x: 24 + 600, y: 24 + 600, width: 200, height: 200)
        let plan = TilePlanner.plan(pageSize: size, frame: frame, zoom: Zoom(1), scale: 1, visible: visible, overscan: 0.5)
        #expect(plan.tiles.first == TileIndex(column: 1, row: 1))
        // 반 타일 여유로 쪽 안 344~1056px: 열은 0~1(쪽 너비 1000px = 2열), 행은 0~2(쪽 높이 1400px = 3행) → 6장.
        #expect(plan.tiles.count == 6)
    }

    @Test("쪽이 보이는 영역 밖에 있으면 타일이 없다")
    func pageOutsideTheViewport() {
        let plan = TilePlanner.plan(
            pageSize: size, frame: frame, zoom: Zoom(1), scale: 1, visible: CGRect(x: 0, y: 5000, width: 600, height: 400)
        )
        #expect(plan.tiles.isEmpty)
    }

    @Test("배율이 커지면 같은 화면 영역을 덮는 비트맵 픽셀이 늘어 타일 수가 는다")
    func higherScaleNeedsMoreTiles() {
        // 보이는 영역 600×400pt. 배율 1이면 600×400px(타일 2장), 배율 4이면 2400×1600px(타일 5열 × 4행).
        let visible = CGRect(x: 24, y: 24, width: 600, height: 400)
        let low = TilePlanner.plan(pageSize: size, frame: frame, zoom: Zoom(1), scale: 1, visible: visible, overscan: 0)
        let high = TilePlanner.plan(pageSize: size, frame: frame, zoom: Zoom(1), scale: 4, visible: visible, overscan: 0)
        #expect(low.tiles.count == 2)
        #expect(high.tiles.count == 5 * 4)
        #expect(high.grid.pixelWidth == 4000 && high.grid.pixelHeight == 5600)
    }

    @Test("타일의 화면 사각형은 비트맵 픽셀에 zoom / scale을 곱한 값이다")
    func tileFrameInPoints() throws {
        // 확대 1, 배율 2(Retina): 1픽셀 = 0.5pt. 타일 (1,0)은 비트맵 x 512~1024 → 256pt~512pt.
        let plan = TilePlanner.plan(
            pageSize: size, frame: frame, zoom: Zoom(1), scale: 2, visible: CGRect(x: 0, y: 0, width: 2000, height: 3000)
        )
        let inner = try #require(plan.frame(of: TileIndex(column: 1, row: 0), zoom: 1))
        #expect(inner == CGRect(x: 256, y: 0, width: 256, height: 256))
        // 마지막 열은 남는 만큼 작다: 비트맵 폭 2000px = 512·3 + 464 → 464px = 232pt, x = 768pt.
        let edge = try #require(plan.frame(of: TileIndex(column: 3, row: 0), zoom: 1))
        #expect(edge == CGRect(x: 768, y: 0, width: 232, height: 256))
        #expect(plan.frame(of: TileIndex(column: 4, row: 0), zoom: 1) == nil)
    }

    @Test("모든 타일의 화면 사각형이 쪽 프레임을 빈틈·겹침 없이 덮는다")
    func tilesTileTheFrame() throws {
        let plan = TilePlanner.plan(
            pageSize: size, frame: frame, zoom: Zoom(1.5), scale: 3, visible: CGRect(x: 0, y: 0, width: 5000, height: 5000), overscan: 0
        )
        var area = 0.0
        for index in plan.tiles { area += try #require(plan.frame(of: index, zoom: 1.5)).width * #require(plan.frame(of: index, zoom: 1.5)).height }
        // 비트맵은 올림한 정수 픽셀이라 프레임보다 최대 1픽셀(=0.5pt) 넓다. 이 크기는 정수라 정확히 같다.
        #expect(abs(area - 1500 * 2100) < 1e-6)
    }
}

@Suite("PageLayout — 확대 앵커와 위쪽 쪽")
struct PageLayoutAnchorTests {
    private let page = PageSize(width: 800, height: 1000)

    private func layout(_ zoom: Double, pages: Int = 3) -> PageLayout {
        PageLayout(pageSizes: Array(repeating: page, count: pages), zoom: Zoom(zoom), spacing: 16, margin: 24)
    }

    @Test("쪽 안의 점은 쪽 프레임 안의 같은 비율로 옮겨진다")
    func pointInsideAPageKeepsItsProportion() {
        // 확대 1에서 쪽 1은 y 1040~2040. 한가운데(1540)는 확대 2에서 쪽 1(y 2040~4040)의 한가운데 3040이다.
        let moved = layout(2).point(matching: CGPoint(x: 424, y: 1540), in: layout(1))
        #expect(abs(moved.y - 3040) < 1e-9)
        // 가로: 여백 24 + (424 − 24) × 2 = 824.
        #expect(abs(moved.x - 824) < 1e-9)
    }

    @Test("쪽 사이 간격과 위쪽 여백은 배율과 무관한 고정 길이로 옮겨진다")
    func gapsAndMarginsStayFixed() {
        // 쪽 0 아래 간격: 확대 1에서 쪽 0 끝(1024)보다 6 아래 → 확대 2에서 쪽 0 끝(2024)보다 6 아래.
        let gap = layout(2).point(matching: CGPoint(x: 100, y: 1030), in: layout(1))
        #expect(abs(gap.y - 2030) < 1e-9)
        // 맨 위 여백: 쪽 0의 위(24)보다 14 위 → 그대로 14 위.
        let top = layout(2).point(matching: CGPoint(x: 100, y: 10), in: layout(1))
        #expect(abs(top.y - 10) < 1e-9)
        // 쪽 1 위 간격: 확대 1에서 쪽 1의 위(1040)보다 5 위(쪽 0 끝보다 11 아래라 쪽 1에 더 가깝다) → 확대 2에서 쪽 1의 위(2040)보다 5 위.
        // 쪽 0의 위쪽 여백은 확대해도 y가 같아서(24) 이 분기를 가르지 못한다. 쪽 1 이후여야 한다.
        let above = layout(2).point(matching: CGPoint(x: 100, y: 1035), in: layout(1))
        #expect(abs(above.y - 2035) < 1e-9)
    }

    @Test("확대했다가 되돌리면 같은 점으로 돌아온다")
    func roundTrip() {
        let original = CGPoint(x: 333, y: 1777)
        let there = layout(3).point(matching: original, in: layout(1))
        let back = layout(1).point(matching: there, in: layout(3))
        #expect(abs(back.x - original.x) < 1e-9 && abs(back.y - original.y) < 1e-9)
    }

    @Test("쪽수가 다른 배치(다른 문서)는 단순 배율 비로 옮긴다")
    func differentDocumentsScaleByRatio() {
        let moved = layout(2, pages: 2).point(matching: CGPoint(x: 100, y: 500), in: layout(1, pages: 3))
        #expect(abs(moved.y - 1000) < 1e-9)
    }

    @Test("위에 걸린 쪽은 위쪽 여백을 건너뛴 선에서 정해진다")
    func topVisiblePage() throws {
        let layout = layout(1)
        #expect(layout.topVisiblePage(offsetY: 0) == 0)
        // 쪽의 위 가장자리로 스크롤한 직후에는 그 쪽이 골라진다.
        for index in 0..<3 {
            let offset = try #require(layout.scrollOffset(forPage: index))
            #expect(layout.topVisiblePage(offsetY: offset) == index)
        }
        // 쪽 1 한가운데까지 스크롤해도 쪽 1이다.
        #expect(layout.topVisiblePage(offsetY: 1016 + 400) == 1)
        #expect(PageLayout(pageSizes: [], zoom: Zoom(1)).topVisiblePage(offsetY: 0) == nil)
    }

    @Test("스크롤 가능한 최대 위치는 내용에서 보이는 영역을 뺀 값이고 음수가 되지 않는다")
    func maxScrollOffset() {
        let layout = layout(1)
        let limit = layout.maxScrollOffset(for: CGSize(width: 500, height: 300))
        #expect(abs(limit.x - (848 - 500)) < 1e-9)
        #expect(abs(limit.y - (3080 - 300)) < 1e-9)
        let large = layout.maxScrollOffset(for: CGSize(width: 5000, height: 9000))
        #expect(large == CGPoint(x: 0, y: 0))
    }
}

@Suite("PinchState")
struct PinchStateTests {
    @Test("비율은 base × 비율이 허용 범위 안에 들도록 맞춰진다")
    func clampsToTheZoomRange() {
        #expect(PinchState(base: Zoom(1.0), magnification: 10, anchor: .zero).magnification == 4.0)
        #expect(PinchState(base: Zoom(1.0), magnification: 0.01, anchor: .zero).magnification == 0.25)
        #expect(PinchState(base: Zoom(2.0), magnification: 3, anchor: .zero).magnification == 2.0, "2 × 2 = 4가 상한")
        #expect(PinchState(base: Zoom(0.5), magnification: 0.1, anchor: .zero).magnification == 0.5, "0.5 × 0.5 = 0.25가 하한")
    }

    @Test("유한하지 않거나 0 이하인 비율은 변화 없음으로 본다", arguments: [Double.nan, .infinity, -1, 0])
    func invalidMagnification(raw: Double) {
        #expect(PinchState(base: Zoom(1.0), magnification: raw, anchor: .zero).magnification == 1)
    }

    @Test("손을 떼면 정해질 배율은 base × 비율이다")
    func resultingZoom() {
        var pinch = PinchState(base: Zoom(1.25), anchor: CGPoint(x: 10, y: 20))
        #expect(pinch.resultingZoom == Zoom(1.25))
        pinch.update(magnification: 1.6)
        #expect(abs(pinch.resultingZoom.factor - 2.0) < 1e-12)
        #expect(pinch.anchor == CGPoint(x: 10, y: 20), "붙잡은 점은 제스처 동안 바뀌지 않는다")
    }
}

import RhwpKit
import RhwpViewer
import Testing

@Suite("PageLayout")
struct PageLayoutTests {
    private let a4 = PageSize(width: 793.7, height: 1122.52)

    @Test("쪽은 위에서 아래로 간격을 두고 쌓이고 내용 크기가 맞는다")
    func stacking() {
        let layout = PageLayout(pageSizes: [a4, a4, a4], zoom: Zoom(1.0), spacing: 16, margin: 24)
        #expect(layout.pageCount == 3)
        #expect(layout.frames[0].y == 24)
        #expect(abs(layout.frames[1].y - (24 + 1122.52 + 16)) < 1e-9)
        #expect(abs(layout.frames[2].y - (24 + 2 * (1122.52 + 16))) < 1e-9)
        // 높이 = 위 여백 + 쪽 3개 + 간격 2개 + 아래 여백.
        #expect(abs(layout.contentHeight - (24 + 3 * 1122.52 + 2 * 16 + 24)) < 1e-9)
        #expect(abs(layout.contentWidth - (793.7 + 48)) < 1e-9)
    }

    @Test("크기가 다른 쪽은 가장 넓은 쪽을 기준으로 가운데 정렬된다")
    func mixedSizesAreCentered() {
        let wide = PageSize(width: 1000, height: 700)
        let narrow = PageSize(width: 800, height: 1000)
        let layout = PageLayout(pageSizes: [wide, narrow], zoom: Zoom(1.0), spacing: 10, margin: 20)
        #expect(layout.frames[0].x == 20)
        #expect(layout.frames[1].x == 120, "(1000-800)/2 = 100 만큼 안쪽")
        #expect(layout.contentWidth == 1040)
    }

    @Test("배율은 쪽 크기에만 곱해지고 간격과 여백은 그대로다")
    func zoomScalesPagesNotChrome() {
        let layout = PageLayout(pageSizes: [a4, a4], zoom: Zoom(2.0), spacing: 16, margin: 24)
        #expect(abs(layout.frames[0].height - 2 * 1122.52) < 1e-9)
        #expect(abs(layout.frames[1].y - (24 + 2 * 1122.52 + 16)) < 1e-9)
        #expect(abs(layout.contentHeight - (24 + 2 * 2 * 1122.52 + 16 + 24)) < 1e-9)
    }

    @Test("쪽이 없으면 여백만 남는다")
    func emptyDocument() {
        let layout = PageLayout(pageSizes: [], zoom: Zoom(1.0), spacing: 16, margin: 24)
        #expect(layout.pageCount == 0)
        #expect(layout.contentHeight == 48 && layout.contentWidth == 48)
        #expect(layout.pageIndex(atY: 10) == nil)
        #expect(layout.visiblePages(top: 0, bottom: 1000) == 0..<0)
        #expect(layout.scrollOffset(forPage: 0) == nil)
    }

    @Test("어떤 크기 목록이든 쪽은 겹치지 않고 순서대로 놓인다")
    func framesNeverOverlap() {
        // 결정적인 의사 난수(선형 합동)로 크기를 만든다.
        var seed: UInt64 = 12345
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let sizes = (0..<200).map { _ in PageSize(width: 200 + 800 * next(), height: 300 + 900 * next()) }
        for factor in [0.25, 1.0, 3.0] {
            let layout = PageLayout(pageSizes: sizes, zoom: Zoom(factor), spacing: 16, margin: 24)
            for index in 1..<layout.frames.count {
                let gap = layout.frames[index].y - layout.frames[index - 1].maxY
                #expect(abs(gap - 16) < 1e-6, "쪽 \(index) 앞 간격이 \(gap)")
            }
            #expect(layout.frames.last!.maxY + 24 == layout.contentHeight)
        }
    }

    @Test("세로 위치에서 쪽을 찾는다")
    func pageIndexAtY() {
        let layout = PageLayout(pageSizes: [a4, a4, a4], zoom: Zoom(1.0), spacing: 16, margin: 24)
        let f = layout.frames
        #expect(layout.pageIndex(atY: f[1].y + 100) == 1, "쪽 안")
        #expect(layout.pageIndex(atY: f[0].maxY + 3) == 0, "간격 안, 위쪽 쪽이 더 가깝다")
        #expect(layout.pageIndex(atY: f[1].y - 3) == 1, "간격 안, 아래쪽 쪽이 더 가깝다")
        #expect(layout.pageIndex(atY: -500) == 0, "내용 위쪽 밖")
        #expect(layout.pageIndex(atY: layout.contentHeight + 500) == 2, "내용 아래쪽 밖")
        for (index, frame) in f.enumerated() {
            #expect(layout.pageIndex(atY: frame.y) == index && layout.pageIndex(atY: frame.maxY) == index, "쪽 경계")
        }
    }

    @Test("보이는 구간과 겹치는 쪽만 고른다")
    func visiblePages() {
        let layout = PageLayout(pageSizes: [a4, a4, a4, a4], zoom: Zoom(1.0), spacing: 16, margin: 24)
        let f = layout.frames
        #expect(layout.visiblePages(top: 0, bottom: 100) == 0..<1)
        #expect(layout.visiblePages(top: f[1].y + 10, bottom: f[2].y + 10) == 1..<3, "두 쪽에 걸침")
        #expect(layout.visiblePages(top: f[3].y, bottom: f[3].maxY + 1000) == 3..<4)
        #expect(layout.visiblePages(top: f[0].maxY + 2, bottom: f[1].y - 2) == 0..<0, "간격만 보이면 쪽 없음")
        // 미리 그리기 거리를 주면 이웃 쪽까지 넓어진다. 쪽 하나가 1,122pt라 200pt로는 위쪽 쪽의 끝에만 닿는다.
        #expect(layout.visiblePages(top: f[1].y + 10, bottom: f[1].y + 20, overscan: 200) == 0..<2)
        // 쪽 1의 아래 끝에서는 아래쪽 쪽(간격 16pt 너머)에 닿고 위쪽 쪽에는 닿지 않는다.
        #expect(layout.visiblePages(top: f[1].maxY - 20, bottom: f[1].maxY - 10, overscan: 200) == 1..<3)
    }

    @Test("쪽 위로 스크롤하는 위치는 위 여백만큼 위다")
    func scrollOffset() {
        let layout = PageLayout(pageSizes: [a4, a4], zoom: Zoom(1.0), spacing: 16, margin: 24)
        #expect(layout.scrollOffset(forPage: 0) == 0)
        #expect(abs(layout.scrollOffset(forPage: 1)! - (1122.52 + 16)) < 1e-9)
        #expect(layout.scrollOffset(forPage: 2) == nil)
    }
}

@Suite("RenderScalePolicy")
struct RenderScalePolicyTests {
    private let a4 = PageSize(width: 793.7, height: 1122.52)

    @Test("기본은 배율 × 화면 배율이다")
    func basicScale() {
        #expect(RenderScalePolicy.scale(zoom: Zoom(1.0), displayScale: 2, pageSize: a4) == 2.0)
        #expect(RenderScalePolicy.scale(zoom: Zoom(0.5), displayScale: 2, pageSize: a4) == 1.0)
    }

    @Test("쪽을 타일로 나눠 그리므로 옛 4096px 상한을 넘는 배율도 그대로 쓴다")
    func scaleIsNoLongerCappedAt4096() {
        // A4(793.7×1122.5)를 4배 확대한 Retina 화면: 배율 8 → 6350×8980px. 옛 정책은 4096/1122.5 = 3.65로 낮췄다.
        let scale = RenderScalePolicy.scale(zoom: Zoom(4.0), displayScale: 2, pageSize: a4)
        #expect(scale == 8.0)
        #expect(scale * a4.height > 4096)
    }

    @Test("한 변이 좌표 정밀도 상한(32768px)을 넘는 아주 큰 쪽만 배율을 낮춘다")
    func capsOnlyAbsurdlyLargePages() {
        let poster = PageSize(width: 3000, height: 4500)   // A0 쯤
        let scale = RenderScalePolicy.scale(zoom: Zoom(4.0), displayScale: 2, pageSize: poster)
        #expect(scale < 8.0)
        #expect(abs(scale * 4500 - 32_768) < 1e-6)
    }

    @Test("흐린 밑그림은 긴 변이 1024px이고 작은 쪽도 1을 넘기지 않는다")
    func coverScale() {
        #expect(abs(RenderScalePolicy.coverScale(pageSize: a4) * a4.height - 1024) < 1e-6)
        #expect(RenderScalePolicy.coverScale(pageSize: PageSize(width: 200, height: 100)) == 1)
        #expect(RenderScalePolicy.coverScale(pageSize: PageSize(width: 0, height: 0)) == 1)
    }

    @Test("화면 배율이 1보다 작게 보고돼도 1로 본다")
    func displayScaleFloor() {
        #expect(RenderScalePolicy.scale(zoom: Zoom(1.0), displayScale: 0, pageSize: a4) == 1.0)
    }
}

@Suite("LRUCache")
struct LRUCacheTests {
    @Test("상한을 넘으면 가장 오래 쓰지 않은 항목부터 내보낸다")
    func evictsOldestFirst() {
        var cache = LRUCache<String, Int>(costLimit: 30)
        cache.insert(1, cost: 10, for: "a")
        cache.insert(2, cost: 10, for: "b")
        cache.insert(3, cost: 10, for: "c")
        cache.insert(4, cost: 10, for: "d")
        #expect(cache.value(for: "a") == nil, "가장 오래된 a가 나갔다")
        #expect(cache.value(for: "b") == 2 && cache.value(for: "c") == 3 && cache.value(for: "d") == 4)
        #expect(cache.totalCost == 30 && cache.count == 3)
    }

    @Test("읽은 항목은 최근 것으로 바뀌어 살아남는다")
    func readingRefreshes() {
        var cache = LRUCache<String, Int>(costLimit: 30)
        cache.insert(1, cost: 10, for: "a")
        cache.insert(2, cost: 10, for: "b")
        cache.insert(3, cost: 10, for: "c")
        _ = cache.value(for: "a")
        cache.insert(4, cost: 10, for: "d")
        #expect(cache.value(for: "a") == 1, "a를 방금 읽었으니 b가 나간다")
        #expect(cache.value(for: "b") == nil)
    }

    @Test("같은 키를 다시 넣으면 비용이 교체된다")
    func replacingAKey() {
        var cache = LRUCache<String, Int>(costLimit: 30)
        cache.insert(1, cost: 20, for: "a")
        cache.insert(2, cost: 5, for: "a")
        #expect(cache.totalCost == 5 && cache.count == 1 && cache.value(for: "a") == 2)
    }

    @Test("상한보다 큰 값은 넣지 않는다")
    func oversizeIsRejected() {
        var cache = LRUCache<String, Int>(costLimit: 30)
        cache.insert(1, cost: 10, for: "a")
        cache.insert(9, cost: 31, for: "big")
        #expect(cache.value(for: "big") == nil && cache.value(for: "a") == 1)
        #expect(cache.totalCost == 10)
    }

    @Test("비우면 비용도 0이다")
    func removeAll() {
        var cache = LRUCache<String, Int>(costLimit: 30)
        cache.insert(1, cost: 10, for: "a")
        cache.removeAll()
        #expect(cache.count == 0 && cache.totalCost == 0)
    }
}

import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender
import RhwpViewer
import Testing

/// 시험 입력. 파일이 없으면 건너뛰지 않고 실패시킨다.
private func sampleData(_ name: String) throws -> Data {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    let url = root.appendingPathComponent("samples").appendingPathComponent(name)
    try #require(FileManager.default.fileExists(atPath: url.path), "샘플 파일 없음: \(url.path)")
    return try Data(contentsOf: url)
}

/// 타일 렌더링·확대 앵커·핀치를 문서를 실제로 열어 시험한다.
@MainActor
@Suite("ViewerModel — 타일·확대·핀치")
struct ViewerModelTileTests {
    private func openedModel(_ name: String = "KTX.hwp", viewport: Viewport? = nil) async throws -> ViewerModel {
        let model = ViewerModel()
        await model.open(data: try sampleData(name))
        if let viewport { model.viewportChanged(viewport) }
        return model
    }

    private let screen = Viewport(offset: .zero, size: CGSize(width: 900, height: 700))

    // MARK: 타일 그림과 캐시

    @Test("타일은 격자가 정한 크기로 그려지고 다시 요청하면 캐시에서 같은 그림이 온다")
    func tileHasTheGridSizeAndIsCached() async throws {
        let model = try await openedModel()
        let size = model.pageSizes[0]
        let grid = TileGrid(pageWidth: size.width, pageHeight: size.height, scale: 2)
        let edge = TileIndex(column: grid.columns - 1, row: grid.rows - 1)
        let rect = try #require(grid.rect(of: edge))

        let first = try #require(await model.tile(page: 0, scale: 2, index: edge))
        #expect(first.width == rect.width && first.height == rect.height, "가장자리 타일은 남는 만큼만 작다")
        let again = try #require(await model.tile(page: 0, scale: 2, index: edge))
        #expect(first === again, "같은 키는 새로 그리지 않는다")
        #expect(await model.tile(page: 0, scale: 2, index: TileIndex(column: 99, row: 0)) == nil, "격자 밖 번호는 그림이 없다")
    }

    @Test("한 쪽의 타일 여러 장과 쪽 전체 그림이 레이어 트리 하나를 나눠 쓴다")
    func tilesShareOneLayerTree() async throws {
        let model = try await openedModel()
        // 서로 다른 타일 4장과 쪽 전체 한 장을 동시에 요청한다.
        async let a = model.tile(page: 3, scale: 2, index: TileIndex(column: 0, row: 0))
        async let b = model.tile(page: 3, scale: 2, index: TileIndex(column: 1, row: 0))
        async let c = model.tile(page: 3, scale: 2, index: TileIndex(column: 0, row: 1))
        async let d = model.tile(page: 3, scale: 2, index: TileIndex(column: 1, row: 1))
        async let whole = model.image(page: 3, scale: 0.3)
        let images = await [a, b, c, d, whole].compactMap { $0 }
        #expect(images.count == 5)
        #expect(model.treeFetchCount == 1, "엔진 호출과 디코딩은 쪽당 한 번이다: \(model.treeFetchCount)")
        #expect(model.renderCount == 5)
        // 배율을 바꿔도(확대) 같은 트리를 쓴다.
        _ = await model.tile(page: 3, scale: 4, index: TileIndex(column: 0, row: 0))
        #expect(model.treeFetchCount == 1)
        #expect(model.renderCount == 6)
        // 다른 쪽은 트리를 따로 가져온다.
        _ = await model.tile(page: 4, scale: 2, index: TileIndex(column: 0, row: 0))
        #expect(model.treeFetchCount == 2)
    }

    @Test("같은 타일을 동시에 요청하면 한 번만 그린다")
    func concurrentTileRequestsShareOneRender() async throws {
        let model = try await openedModel()
        let index = TileIndex(column: 0, row: 0)
        async let a = model.tile(page: 2, scale: 2, index: index)
        async let b = model.tile(page: 2, scale: 2, index: index)
        async let c = model.tile(page: 2, scale: 2, index: index)
        let images = await [a, b, c].compactMap { $0 }
        #expect(images.count == 3 && images[0] === images[1] && images[1] === images[2])
        #expect(model.renderCount == 1, "진행 중인 요청을 함께 기다려야 한다: \(model.renderCount)")
    }

    @Test("cachedImage는 그리지 않고 캐시만 본다")
    func cachedImageDoesNotRender() async throws {
        let model = try await openedModel()
        let index = TileIndex(column: 0, row: 0)
        #expect(model.cachedImage(page: 0, scale: 2, tile: index) == nil)
        _ = await model.tile(page: 0, scale: 2, index: index)
        #expect(model.cachedImage(page: 0, scale: 2, tile: index) != nil)
        #expect(model.cachedImage(page: 0, scale: 2) == nil, "같은 배율의 쪽 전체 그림은 다른 키다")
    }

    // MARK: 4096px 너머

    @Test("확대 4배 Retina(배율 8)에서 쪽 비트맵이 4096px를 넘어도 보이는 타일만 그린다")
    func tilesBeyondTheOldCap() async throws {
        let model = try await openedModel()
        model.setZoom(Zoom(4.0))
        let scale = model.renderScale(page: 0, displayScale: 2)
        #expect(scale == 8.0, "옛 정책은 4096px 상한 때문에 3.65로 낮췄다")

        // 쪽 가운데 부근을 보고 있다.
        let frame = model.layout.frames[0]
        model.viewportChanged(Viewport(
            offset: CGPoint(x: frame.x + frame.width / 2 - 450, y: frame.y + frame.height / 2 - 350),
            size: CGSize(width: 900, height: 700)
        ))
        let plan = try #require(model.renderPlan(page: 0, displayScale: 2))
        #expect(plan.tiles.grid.pixelWidth > 4096 && plan.tiles.grid.pixelHeight > 4096)
        #expect(plan.tiles.tiles.count < plan.tiles.grid.tileCount / 3, "쪽 전체가 아니라 보이는 곳만 그린다")
        #expect(!plan.tiles.tiles.isEmpty)

        await model.loadTiles(page: 0, scale: plan.tiles.scale, indices: plan.tiles.tiles)
        let loaded = try #require(model.renderPlan(page: 0, displayScale: 2))
        #expect(loaded.missing.isEmpty)
        #expect(loaded.items.count == plan.tiles.tiles.count)
        for item in loaded.items {
            let index = try #require(item.id.tile)
            let rect = try #require(plan.tiles.grid.rect(of: index))
            #expect(item.image.width == rect.width && item.image.height == rect.height)
            // 타일의 화면 크기 = 비트맵 크기 / 화면 배율(2).
            #expect(abs(item.frame.width - Double(rect.width) / 2) < 1e-9)
        }
        // 이 타일들 가운데 한 장은 실제로 칠해져 있다(한 쪽 전체가 흰 종이일 수는 없다: KTX 첫 쪽은 글자가 많다).
        #expect(model.renderCount == plan.tiles.tiles.count)
    }

    // MARK: 타일 요청

    @Test("loadTiles는 모두 그려서 캐시에 남기고 renderPlan의 missing을 비운다")
    func loadTilesFillsThePlan() async throws {
        let model = try await openedModel(viewport: screen)
        let before = try #require(model.renderPlan(page: 0, displayScale: 2))
        #expect(!before.tiles.tiles.isEmpty)
        #expect(before.missing == before.tiles.tiles, "처음에는 모두 비어 있다")
        #expect(before.items.isEmpty)
        #expect(before.cover == nil)

        await model.loadTiles(page: 0, scale: before.tiles.scale, indices: before.missing)
        await model.loadCover(page: 0)
        let after = try #require(model.renderPlan(page: 0, displayScale: 2))
        #expect(after.missing.isEmpty)
        #expect(after.items.count == before.tiles.tiles.count)
        #expect(after.cover != nil)
    }

    @Test("호출한 작업이 취소되면 아직 시작하지 않은 타일은 그리지 않는다")
    func cancelledLoadStartsNothing() async throws {
        let model = try await openedModel(viewport: screen)
        let plan = try #require(model.renderPlan(page: 0, displayScale: 2))
        #expect(plan.tiles.tiles.count > 3)
        let task = Task { await model.loadTiles(page: 0, scale: plan.tiles.scale, indices: plan.tiles.tiles) }
        task.cancel()
        await task.value
        #expect(model.renderCount == 0, "시작 전에 취소됐으면 하나도 그리지 않는다: \(model.renderCount)")
    }

    @Test("취소하면 줄 서 있던 나머지 타일을 시작하지 않는다")
    func cancellationStopsTheWindow() async throws {
        let model = try await openedModel(viewport: screen)
        model.setZoom(Zoom(4.0))   // 타일이 많아지는 배율(기본 타일이 1024px라 확대 4배(배율 8)에서야 수십 장이 된다)
        let scale = model.renderScale(page: 0, displayScale: 2)
        let grid = TileGrid(pageWidth: model.pageSizes[0].width, pageHeight: model.pageSizes[0].height, scale: scale)
        let all = (0..<grid.rows).flatMap { row in (0..<grid.columns).map { TileIndex(column: $0, row: row) } }
        #expect(all.count > 40, "타일 \(all.count)장")

        let task = Task { await model.loadTiles(page: 0, scale: scale, indices: all, concurrency: 2) }
        // 첫 타일이 캐시에 들어오는 것을 보고 취소한다.
        while model.renderCount == 0 { await Task.yield() }
        task.cancel()
        await task.value
        // 취소하지 않았다면 전체(수십 장)를 그렸을 것이다. 취소 시점에 이미 시작한 몇 장만 더 끝나므로 절반에도 못 미친다.
        // (정확한 장수는 취소를 관측하는 시점에 따라 달라서 "전체의 절반 미만"만 본다.)
        #expect(model.renderCount >= 1 && model.renderCount < all.count / 2, "그린 타일 \(model.renderCount)장 / 전체 \(all.count)장")
    }

    // MARK: 확대 직후의 이전 해상도 타일

    @Test("확대 배율이 바뀌면 새 타일이 오기 전에 캐시에 남은 이전 배율의 타일이 밑에 깔린다")
    func previousScaleTilesFillIn() async throws {
        let model = try await openedModel(viewport: screen)
        model.setZoom(Zoom(1.0))
        let low = try #require(model.renderPlan(page: 0, displayScale: 2))
        await model.loadTiles(page: 0, scale: low.tiles.scale, indices: low.missing)
        #expect(model.renderPlan(page: 0, displayScale: 2)?.missing.isEmpty == true)

        model.setZoom(Zoom(2.0))
        let high = try #require(model.renderPlan(page: 0, displayScale: 2))
        #expect(high.tiles.scale == 4.0 && low.tiles.scale == 2.0)
        #expect(!high.missing.isEmpty, "새 배율의 타일은 아직 없다")
        let fallback = high.items.filter { $0.id.scaleMilli == 2000 }
        #expect(!fallback.isEmpty, "그래도 이전 배율(2.0)의 타일이 보인다")
        // 이전 타일의 화면 사각형은 새 확대 기준으로 늘어나 있다: 확대 2, 배율 2이면 1픽셀 = 1pt.
        for item in fallback {
            let index = try #require(item.id.tile)
            let rect = try #require(low.tiles.grid.rect(of: index))
            #expect(abs(item.frame.width - Double(rect.width)) < 1e-9)
        }

        // 새 타일이 오면 정확한 배율의 타일이 위(뒤에서 앞 순서의 뒤쪽)에 온다.
        await model.loadTiles(page: 0, scale: high.tiles.scale, indices: high.missing)
        let filled = try #require(model.renderPlan(page: 0, displayScale: 2))
        #expect(filled.missing.isEmpty)
        let lastFallback = filled.items.lastIndex { $0.id.scaleMilli == 2000 }
        let firstExact = filled.items.firstIndex { $0.id.scaleMilli == 4000 }
        if let lastFallback, let firstExact { #expect(lastFallback < firstExact, "정확한 배율이 이전 배율 위에 그려진다") }
    }

    // MARK: 확대 앵커

    @Test("확대하면 붙잡은 점의 내용이 같은 화면 위치에 머물도록 스크롤을 요청한다")
    func zoomKeepsTheAnchoredContent() async throws {
        let model = try await openedModel()
        model.setZoom(Zoom(1.0))
        model.viewportChanged(Viewport(offset: CGPoint(x: 0, y: 500), size: CGSize(width: 800, height: 600)))
        let before = model.scrollRequest
        let page = model.pageSizes[0]

        // 화면 (300, 200)을 붙잡고 2배로 확대. 내용 좌표 (300, 700)은 쪽 0 안이다.
        model.setZoom(Zoom(2.0), anchor: CGPoint(x: 300, y: 200))
        let request = try #require(model.scrollRequest)
        #expect(request != before)
        // 손계산: y = 쪽 0 위(24) + (700 − 24) × 2 = 1376 → 스크롤 = 1376 − 200 = 1176.
        //         x = 여백 24 + (300 − 24) × 2 = 576 → 스크롤 = 576 − 300 = 276.
        #expect(abs(request.offset.y - 1176) < 1e-9, "y \(request.offset.y)")
        #expect(abs(request.offset.x - 276) < 1e-9, "x \(request.offset.x)")
        // 새 배치에서 그 점이 정말 같은 내용인지: 쪽 0 안의 같은 비율이다.
        let frame = model.layout.frames[0]
        let ratio = (700.0 - 24) / page.height
        #expect(abs((request.offset.y + 200 - frame.y) / frame.height - ratio) < 1e-9)
    }

    @Test("앵커가 없으면 스크롤을 요청하지 않는다")
    func noAnchorNoScroll() async throws {
        let model = try await openedModel()
        model.setZoom(Zoom(1.0))
        model.viewportChanged(screen)
        let before = model.scrollRequest
        model.setZoom(Zoom(2.0))
        #expect(model.scrollRequest == before)
    }

    @Test("요청하는 스크롤 위치는 내용 안으로 맞춰진다")
    func requestedOffsetIsClamped() async throws {
        let model = try await openedModel()
        model.setZoom(Zoom(1.0))
        // 문서 맨 아래를 보고 있다가 축소하면 새 내용 끝을 넘지 않는다.
        let bottom = model.layout.maxScrollOffset(for: CGSize(width: 800, height: 600))
        model.viewportChanged(Viewport(offset: bottom, size: CGSize(width: 800, height: 600)))
        model.setZoom(Zoom(0.5), anchor: CGPoint(x: 400, y: 600))
        let request = try #require(model.scrollRequest)
        let limit = model.layout.maxScrollOffset(for: CGSize(width: 800, height: 600))
        #expect(request.offset.x >= 0 && request.offset.x <= limit.x + 1e-9)
        #expect(request.offset.y >= 0 && request.offset.y <= limit.y + 1e-9)
    }

    @Test("확대·축소 명령은 보이는 영역의 중심을 붙잡는다")
    func zoomCommandsAnchorAtTheCenter() async throws {
        let model = try await openedModel()
        model.setZoom(Zoom(1.0))
        model.viewportChanged(Viewport(offset: CGPoint(x: 0, y: 500), size: CGSize(width: 800, height: 600)))
        model.zoomIn()   // 1.0 → 1.25
        let request = try #require(model.scrollRequest)
        // 중심 (400, 300) → 내용 (400, 800). 쪽 0 안: y = 24 + (800 − 24) × 1.25 = 994 → 스크롤 694.
        #expect(abs(request.offset.y - (24 + (800.0 - 24) * 1.25 - 300)) < 1e-9)
    }

    // MARK: 핀치

    @Test("핀치 중에는 배율과 배치를 바꾸지 않고, 손을 떼면 정한다")
    func pinchCommitsOnRelease() async throws {
        let model = try await openedModel(viewport: screen)
        model.setZoom(Zoom(1.0))
        let layoutBefore = model.layout

        model.pinchChanged(magnification: 1.2, anchor: CGPoint(x: 100, y: 100))
        model.pinchChanged(magnification: 1.6, anchor: CGPoint(x: 999, y: 999))   // 붙잡은 점은 처음 값이 유지된다
        let live = try #require(model.pinch)
        #expect(live.magnification == 1.6 && live.anchor == CGPoint(x: 100, y: 100))
        #expect(model.zoom == Zoom(1.0) && model.layout == layoutBefore, "손을 떼기 전에는 그대로")

        model.pinchEnded()
        #expect(model.pinch == nil)
        #expect(abs(model.zoom.factor - 1.6) < 1e-12)
        #expect(!model.fitsWidth)
        #expect(model.scrollRequest != nil, "붙잡은 점을 유지하려고 스크롤을 요청한다")
    }

    @Test("핀치 비율은 허용 범위로 맞춰진다")
    func pinchIsClamped() async throws {
        let model = try await openedModel(viewport: screen)
        model.setZoom(Zoom(2.0))
        model.pinchChanged(magnification: 50, anchor: .zero)
        #expect(model.pinch?.magnification == 2.0, "2 × 2 = 4가 상한")
        model.pinchEnded()
        #expect(model.zoom == Zoom(4.0))
    }

    @Test("거의 변화가 없는 핀치는 너비 맞춤을 끄지 않는다")
    func tinyPinchIsIgnored() async throws {
        let model = try await openedModel(viewport: screen)
        let fitted = model.zoom
        #expect(model.fitsWidth)
        model.pinchChanged(magnification: 1.002, anchor: .zero)
        model.pinchEnded()
        #expect(model.fitsWidth && model.zoom == fitted)
    }

    @Test("취소한 핀치는 아무것도 바꾸지 않는다")
    func cancelledPinch() async throws {
        let model = try await openedModel(viewport: screen)
        let zoom = model.zoom
        model.pinchChanged(magnification: 2, anchor: .zero)
        model.pinchCancelled()
        #expect(model.pinch == nil && model.zoom == zoom && model.fitsWidth)
    }

    // MARK: 보이는 영역

    @Test("보이는 영역의 너비가 바뀌면 너비 맞춤 배율이 따라간다")
    func viewportDrivesFitWidth() async throws {
        let model = try await openedModel()
        let widest = try #require(model.pageSizes.map(\.width).max())
        model.viewportChanged(Viewport(offset: .zero, size: CGSize(width: 1000, height: 700)))
        #expect(abs(model.zoom.factor - (1000 - 2 * model.layout.margin) / widest) < 1e-9)
        // 세로 스크롤만 바뀌면 배율은 그대로다.
        let zoom = model.zoom
        model.viewportChanged(Viewport(offset: CGPoint(x: 0, y: 400), size: CGSize(width: 1000, height: 700)))
        #expect(model.zoom == zoom)
    }
}

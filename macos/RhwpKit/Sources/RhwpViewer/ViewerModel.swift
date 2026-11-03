import CoreGraphics
import Foundation
import Observation
import RhwpKit
import RhwpRender

/// 쪽 그림 캐시의 키. 같은 쪽도 배율이 다르면, 같은 배율이어도 타일이 다르면 다른 그림이다.
public struct RenderKey: Hashable, Sendable {
    public let page: Int
    /// 배율을 1/1000 단위 정수로 둔 값(Double 을 키로 쓰지 않으려는 것).
    public let scaleMilli: Int
    /// 쪽 비트맵의 타일 번호. nil 이면 쪽 전체를 한 장으로 그린 그림(썸네일, 흐린 밑그림)이다.
    public let tile: TileIndex?

    public init(page: Int, scale: Double, tile: TileIndex? = nil) {
        self.page = page
        scaleMilli = Int((scale * 1000).rounded())
        self.tile = tile
    }

    public var scale: Double { Double(scaleMilli) / 1000 }
}

/// 화면에 그릴 타일 한 장.
public struct TileDrawItem: Identifiable, Sendable {
    public let id: RenderKey
    /// 쪽 프레임 안의 위치와 크기(pt, 원점은 쪽 왼쪽 위).
    public let frame: CGRect
    public let image: CGImage
}

/// 쪽 하나를 지금 어떻게 그릴지.
public struct PageRenderPlan: Sendable {
    /// 지금 배율에서 필요한 타일(보이는 영역 + 여유).
    public let tiles: TilePlan
    /// 필요한 타일 중 아직 캐시에 없는 것. 가까운 순이다.
    public let missing: [TileIndex]
    /// 뒤에서 앞으로 그릴 순서의 타일: 캐시에 남은 다른 배율의 타일(먼 배율부터) 위에 정확한 배율의 타일이 온다.
    /// 확대 배율이 바뀐 직후 새 타일이 오기 전까지 흰 종이 대신 이전 해상도의 그림이 보이게 한다.
    public let items: [TileDrawItem]
    /// 쪽 전체의 흐린 밑그림. 아직 없으면 nil.
    public let cover: CGImage?
}

/// 한 문서 창의 뷰어 상태.
///
/// 책임은 넷이다: ① 문서를 열고 쪽 크기를 알아 둔다, ② 확대 배율과 쪽 배치를 정하고 확대할 때 사용자가 붙잡은 곳을 유지한다,
/// ③ 쪽 그림을 비동기로 만들어 캐시한다(쪽 전체 한 장 또는 타일), ④ 핀치 중의 임시 확대 상태를 든다. 엔진 호출은
/// `RhwpDocumentSession`(전용 큐 actor)이, 그리기는 `PageRenderer`가 하고 이 클래스는 메인 액터에서 상태만 들고 있다.
/// 순수 계산(배치·배율·타일 계획·캐시 정책)은 `RhwpViewer` 패키지에 있어 단위 시험이 된다.
///
/// **캐시 단위**(왜 이렇게 나눴나)
/// - 레이어 트리(`PageLayerTree`)는 쪽당 하나다. 한 쪽의 타일 수십 장과 배율 변경이 모두 같은 트리를 쓰므로 타일마다
///   엔진 호출과 JSON 디코딩을 되풀이하지 않는다. 비용은 JSON 바이트 수 × 5로 어림한다(샘플 866쪽 측정에서 트리 메모리는 JSON의 0.9~4.5배였다. `rhwp-render --bench`).
/// - 비트맵(`RenderKey`)은 타일 하나 또는 쪽 전체 한 장이다. 둘 다 같은 384MB LRU에서 바이트 수로 겨룬다.
/// - 같은 키(트리는 같은 쪽)를 동시에 요청하면 하나로 합치고, 요청한 쪽이 취소돼도 시작한 일은 끝까지 가서 캐시에 남는다.
@MainActor
@Observable
public final class ViewerModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var pageSizes: [PageSize] = []
    public private(set) var zoom: Zoom = .actualSize
    public private(set) var layout = PageLayout(pageSizes: [], zoom: .actualSize)

    /// 창 크기에 맞춰 너비 맞춤을 유지하는가. 사용자가 배율을 직접 정하면 꺼진다.
    public private(set) var fitsWidth = true

    /// 스크롤 영역이 지금 보여 주는 곳. 화면이 알려 준다(`viewportChanged`).
    public private(set) var viewport = Viewport.zero
    /// 모델이 화면에 요청하는 스크롤(확대할 때 붙잡은 곳을 유지하려고). 화면이 `serial`이 바뀔 때마다 따른다.
    public private(set) var scrollRequest: ScrollRequest?
    /// 진행 중인 핀치. 있으면 화면이 그 배율만큼 지금 보이는 것을 늘여 보여 준다.
    public private(set) var pinch: PinchState?
    /// 새 타일이 캐시에 들어올 때마다 늘어난다. 화면이 이 값을 읽어 두면 타일이 도착할 때 다시 그린다.
    public private(set) var tileRevision = 0

    @ObservationIgnored private var session: RhwpDocumentSession?
    @ObservationIgnored private let renderer = PageRenderer()
    @ObservationIgnored private var cache = LRUCache<RenderKey, CGImage>(costLimit: 384 * 1024 * 1024)
    @ObservationIgnored private var inFlight: [RenderKey: Task<CGImage?, Never>] = [:]
    @ObservationIgnored private var trees = LRUCache<Int, PageLayerTree>(costLimit: 96 * 1024 * 1024)
    @ObservationIgnored private var treeInFlight: [Int: Task<PageLayerTree?, Never>] = [:]
    /// 쪽마다 타일이 그려진 적 있는 배율(1/1000 단위). 확대 직후 다른 배율의 타일을 밑그림으로 찾는 데 쓴다.
    @ObservationIgnored private var tileScales: [Int: Set<Int>] = [:]
    @ObservationIgnored private var viewportWidth: Double = 0
    @ObservationIgnored private var scrollSerial = 0
    /// 문서를 다시 열 때마다 늘어난다. 이전 문서의 늦은 결과가 새 캐시에 들어오지 않게 한다.
    @ObservationIgnored private var epoch = 0

    /// 진단·시험용 집계: 엔진에서 레이어 트리를 가져온 횟수와 비트맵을 실제로 그린 횟수.
    @ObservationIgnored public private(set) var treeFetchCount = 0
    @ObservationIgnored public private(set) var renderCount = 0

    public var pageCount: Int { pageSizes.count }

    public init() {}

    // MARK: - 열기

    public func open(data: Data) async {
        phase = .loading
        do {
            let session = try await RhwpDocumentSession.open(data: data)
            let sizes = try await session.pageSizes()
            self.session = session
            pageSizes = sizes
            epoch += 1
            cache.removeAll()
            trees.removeAll()
            inFlight.removeAll()
            treeInFlight.removeAll()
            tileScales.removeAll()
            applyZoom(fitsWidth ? fittedZoom() ?? .actualSize : zoom, anchor: nil)
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - 보이는 영역

    /// 스크롤 영역이 보여 주는 곳이 바뀌었다. 너비가 바뀌었고 너비 맞춤 중이면 배율을 다시 맞춘다.
    public func viewportChanged(_ new: Viewport) {
        guard new != viewport else { return }
        viewport = new
        viewportWidthChanged(Double(new.size.width))
    }

    /// 스크롤 영역의 너비(pt)가 바뀌었다. 너비 맞춤 중이면 배율을 다시 맞춘다.
    public func viewportWidthChanged(_ width: Double) {
        guard width > 0, width != viewportWidth else { return }
        viewportWidth = width
        // 창 크기가 바뀔 때는 화면 맨 위에 보이던 내용을 붙잡는다(읽던 줄이 그대로 맨 위에 있다).
        if fitsWidth, let fitted = fittedZoom(), fitted != zoom {
            applyZoom(fitted, anchor: CGPoint(x: viewport.size.width / 2, y: 0))
        }
    }

    // MARK: - 확대·축소

    public func zoomIn() { setZoom(zoom.zoomedIn(), anchor: viewportCenter) }
    public func zoomOut() { setZoom(zoom.zoomedOut(), anchor: viewportCenter) }

    /// 배율을 정한다. `anchor`(보이는 영역 안의 점, pt)에 있던 내용이 확대 뒤에도 같은 자리에 머물도록 스크롤을 요청한다.
    /// nil이면 스크롤 위치를 그대로 둔다.
    public func setZoom(_ newZoom: Zoom, anchor: CGPoint? = nil) {
        fitsWidth = false
        applyZoom(newZoom, anchor: anchor)
    }

    public func actualSize() { setZoom(.actualSize, anchor: viewportCenter) }

    /// 쪽 너비를 창에 맞추고 창 크기가 바뀌어도 그 상태를 유지한다.
    public func fitWidth() {
        fitsWidth = true
        if let fitted = fittedZoom() { applyZoom(fitted, anchor: CGPoint(x: viewport.size.width / 2, y: 0)) }
    }

    /// 보이는 영역의 중심(보이는 영역 좌표). 확대·축소 명령과 메뉴가 붙잡는 점이다. 영역을 모르면 nil.
    public var viewportCenter: CGPoint? {
        viewport.isKnown ? CGPoint(x: viewport.size.width / 2, y: viewport.size.height / 2) : nil
    }

    private func fittedZoom() -> Zoom? {
        guard viewportWidth > 0, let widest = pageSizes.map(\.width).max() else { return nil }
        return Zoom.fitWidth(availableWidth: viewportWidth - 2 * layout.margin, pageWidth: widest)
    }

    private func applyZoom(_ newZoom: Zoom, anchor: CGPoint?) {
        let old = layout
        zoom = newZoom
        layout = PageLayout(pageSizes: pageSizes, zoom: newZoom, spacing: layout.spacing, margin: layout.margin)
        guard let anchor, viewport.isKnown, newZoom != old.zoom else { return }

        // 붙잡은 점의 내용 좌표를 새 배치로 옮기고, 그 점이 같은 화면 위치에 오도록 스크롤 위치를 구한다.
        let content = CGPoint(x: viewport.offset.x + anchor.x, y: viewport.offset.y + anchor.y)
        let moved = layout.point(matching: content, in: old)
        let limit = layout.maxScrollOffset(for: viewport.size)
        let target = CGPoint(
            x: min(max(moved.x - anchor.x, 0), limit.x),
            y: min(max(moved.y - anchor.y, 0), limit.y)
        )
        scrollSerial += 1
        scrollRequest = ScrollRequest(offset: target, serial: scrollSerial)
    }

    // MARK: - 핀치 확대

    /// 핀치가 진행 중이다. `magnification`은 제스처가 시작된 뒤의 누적 비율, `anchor`는 두 손가락 중심(보이는 영역 좌표)이다.
    /// 배율·배치·타일은 손을 뗄 때까지 바꾸지 않는다. 화면이 `pinch`를 읽어 지금 보이는 것을 그 비율만큼 즉시 늘여 보여 준다.
    public func pinchChanged(magnification: Double, anchor: CGPoint) {
        if var current = pinch {
            current.update(magnification: magnification)
            pinch = current
        } else {
            pinch = PinchState(base: zoom, magnification: magnification, anchor: anchor)
        }
    }

    /// 손을 뗐다. 확대 비율을 새 배율로 정하고 그 배율의 타일을 채운다. 거의 변화가 없는 핀치는 배율을 건드리지 않는다
    /// (손가락 떨림이 너비 맞춤을 꺼 버리지 않도록).
    public func pinchEnded() {
        guard let current = pinch else { return }
        pinch = nil
        guard abs(current.magnification - 1) > 0.005 else { return }
        setZoom(current.resultingZoom, anchor: current.anchor)
    }

    /// 핀치가 취소됐다. 배율은 그대로다.
    public func pinchCancelled() { pinch = nil }

    // MARK: - 쪽 그림

    /// 쪽 `page` 전체를 px→비트맵 배율 `scale`로 한 장에 그린 그림(썸네일, 흐린 밑그림). 같은 요청이 진행 중이면 그 결과를
    /// 함께 기다린다. 취소되면 nil 이지만 시작한 그리기는 끝까지 가서 캐시에 남는다(스크롤로 잠깐 벗어난 쪽을 다시 그리지 않는다).
    public func image(page: Int, scale: Double) async -> CGImage? {
        await cachedOrRender(RenderKey(page: page, scale: scale))
    }

    /// 쪽 `page`의 타일 하나를 배율 `scale`로 그린 그림. 요청 합치기와 캐시는 `image(page:scale:)`와 같다.
    public func tile(page: Int, scale: Double, index: TileIndex) async -> CGImage? {
        await cachedOrRender(RenderKey(page: page, scale: scale, tile: index))
    }

    /// 캐시에 있는 그림만 돌려준다(새로 그리지 않는다). 읽으면 최근에 쓴 것으로 표시된다.
    public func cachedImage(page: Int, scale: Double, tile: TileIndex? = nil) -> CGImage? {
        cache.value(for: RenderKey(page: page, scale: scale, tile: tile))
    }

    private func cachedOrRender(_ key: RenderKey) async -> CGImage? {
        if let cached = cache.value(for: key) { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task { await self.produceImage(for: key) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    private func produceImage(for key: RenderKey) async -> CGImage? {
        let epoch = epoch
        guard let tree = await layerTree(page: key.page) else { return nil }
        let renderer = renderer
        let scale = key.scale
        let tile = key.tile
        // 그리기는 메인 액터와 문서 큐 밖에서 한다. 레이어 트리와 렌더러 모두 Sendable 이다.
        let image: CGImage? = await Task.detached(priority: .userInitiated) {
            do {
                if let tile {
                    let grid = TileGrid(pageWidth: tree.pageWidth, pageHeight: tree.pageHeight, scale: scale)
                    guard let rect = grid.rect(of: tile) else { return nil }
                    return try renderer.renderTile(tree, scale: scale, tile: rect).image
                }
                return try renderer.render(tree, scale: scale).image
            } catch {
                return nil
            }
        }.value
        // 그리는 동안 문서가 다시 열렸다면 이 결과는 이전 문서의 것이다.
        guard let image, epoch == self.epoch else { return nil }
        renderCount += 1
        cache.insert(image, cost: image.bytesPerRow * image.height, for: key)
        if tile != nil {
            tileScales[key.page, default: []].insert(key.scaleMilli)
            tileRevision &+= 1
        }
        return image
    }

    // MARK: - 레이어 트리

    /// 쪽의 레이어 트리. 캐시에 있으면 그것을, 같은 쪽을 이미 가져오는 중이면 그 결과를 함께 기다린다.
    ///
    /// 엔진 호출(JSON 생성)만 문서 큐에서 하고 **디코딩은 큐 밖에서** 한다. 큐는 문서 하나의 모든 엔진 호출이 줄 서는 곳이라
    /// 순수 CPU 일인 디코딩이 그 줄을 막지 않게 하려는 것이다(측정은 `mydocs/tech/macos_native_app_architecture.md`의 타일 절).
    private func layerTree(page: Int) async -> PageLayerTree? {
        if let cached = trees.value(for: page) { return cached }
        if let running = treeInFlight[page] { return await running.value }

        let task = Task { await self.fetchLayerTree(page: page) }
        treeInFlight[page] = task
        let tree = await task.value
        treeInFlight[page] = nil
        return tree
    }

    private func fetchLayerTree(page: Int) async -> PageLayerTree? {
        guard let session else { return nil }
        let epoch = epoch
        do {
            let json = try await session.layerTreeJSON(page: page)
            let tree = try await Task.detached(priority: .userInitiated) {
                try PageLayerTree.decode(envelope: json)
            }.value
            guard epoch == self.epoch else { return nil }
            treeFetchCount += 1
            trees.insert(tree, cost: json.count * 5, for: page)
            return tree
        } catch {
            return nil
        }
    }

    // MARK: - 타일 계획

    /// 쪽 `page`의 화면 배율과 현재 확대에 맞는 쪽 그림 배율(캐시 키와 같은 1/1000 반올림).
    public func renderScale(page: Int, displayScale: Double) -> Double {
        guard pageSizes.indices.contains(page) else { return 1 }
        let wanted = RenderScalePolicy.scale(zoom: zoom, displayScale: displayScale, pageSize: pageSizes[page])
        return RenderKey(page: page, scale: wanted).scale
    }

    /// 쪽 하나를 지금 화면에 어떻게 그릴지. 화면이 본문(body)에서 부르면 보이는 영역이 바뀔 때, 새 타일이 도착할 때
    /// (`tileRevision`) 다시 계산된다.
    public func renderPlan(page: Int, displayScale: Double) -> PageRenderPlan? {
        _ = tileRevision
        guard pageSizes.indices.contains(page), layout.frames.indices.contains(page) else { return nil }
        let size = pageSizes[page]
        let frame = layout.frames[page]
        // 첫 보고 전에는 화면 크기를 모른다. 내용 맨 위의 적당한 창을 보이는 것으로 본다.
        let visible = viewport.isKnown ? viewport.visibleRect : CGRect(x: 0, y: 0, width: 1600, height: 1200)

        let scale = renderScale(page: page, displayScale: displayScale)
        let wanted = TilePlanner.plan(pageSize: size, frame: frame, zoom: zoom, scale: scale, visible: visible)

        var items: [TileDrawItem] = []
        // 다른 배율의 타일: 가까운 세 배율만, 먼 것부터 깔고 가까운 것이 위에 온다.
        let current = RenderKey(page: page, scale: scale).scaleMilli
        let others = (tileScales[page] ?? []).subtracting([current])
            .sorted { abs(log(Double($0) / Double(current))) < abs(log(Double($1) / Double(current))) }
            .prefix(3).reversed()
        for milli in others {
            let plan = TilePlanner.plan(
                pageSize: size, frame: frame, zoom: zoom, scale: Double(milli) / 1000, visible: visible, overscan: 0
            )
            for index in plan.tiles {
                let key = RenderKey(page: page, scale: plan.scale, tile: index)
                if let image = cache.value(for: key), let rect = plan.frame(of: index, zoom: zoom.factor) {
                    items.append(TileDrawItem(id: key, frame: rect, image: image))
                }
            }
        }

        var missing: [TileIndex] = []
        for index in wanted.tiles {
            let key = RenderKey(page: page, scale: wanted.scale, tile: index)
            if let image = cache.value(for: key), let rect = wanted.frame(of: index, zoom: zoom.factor) {
                items.append(TileDrawItem(id: key, frame: rect, image: image))
            } else {
                missing.append(index)
            }
        }

        let cover = cache.value(for: RenderKey(page: page, scale: RenderScalePolicy.coverScale(pageSize: size)))
        return PageRenderPlan(tiles: wanted, missing: missing, items: items, cover: cover)
    }

    /// `indices`의 타일을 이 순서대로(가까운 것부터) 그린다. 동시에 `concurrency`장까지만 시작하고, 호출한 작업이 취소되면
    /// 아직 시작하지 않은 타일은 그리지 않는다. 스크롤로 지나친 쪽의 타일 수십 장이 줄을 서서 CPU를 먹지 않게 하려는 것이다.
    /// 이미 시작한 타일은 끝까지 가서 캐시에 남는다.
    public func loadTiles(page: Int, scale: Double, indices: [TileIndex], concurrency: Int = 3) async {
        await withTaskGroup(of: Void.self) { group in
            var next = indices.startIndex
            var running = 0
            while next < indices.endIndex || running > 0 {
                while running < max(concurrency, 1), next < indices.endIndex, !Task.isCancelled {
                    let index = indices[next]
                    next += 1
                    running += 1
                    group.addTask { _ = await self.tile(page: page, scale: scale, index: index) }
                }
                if running == 0 { break }
                await group.next()
                running -= 1
                if Task.isCancelled { next = indices.endIndex }
            }
        }
    }

    /// 쪽 전체의 흐린 밑그림을 그린다(이미 있으면 그대로).
    public func loadCover(page: Int) async {
        guard pageSizes.indices.contains(page) else { return }
        _ = await image(page: page, scale: RenderScalePolicy.coverScale(pageSize: pageSizes[page]))
    }

    /// 사이드바 썸네일 한 장의 배율(px→비트맵). `width`는 썸네일의 화면 너비(pt)다.
    public func thumbnailScale(page: Int, width: Double, displayScale: Double) -> Double {
        guard pageSizes.indices.contains(page), pageSizes[page].width > 0 else { return 1 }
        return width * max(displayScale, 1) / pageSizes[page].width
    }
}

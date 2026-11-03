import CoreGraphics
import Foundation
import Observation
import RhwpKit
import RhwpRender

/// 쪽 그림 캐시의 키. 같은 쪽도 배율이 다르면 다른 그림이다.
public struct RenderKey: Hashable, Sendable {
    public let page: Int
    /// 배율을 1/1000 단위 정수로 둔 값(Double 을 키로 쓰지 않으려는 것).
    public let scaleMilli: Int

    public init(page: Int, scale: Double) {
        self.page = page
        scaleMilli = Int((scale * 1000).rounded())
    }

    public var scale: Double { Double(scaleMilli) / 1000 }
}

/// 한 문서 창의 뷰어 상태.
///
/// 책임은 셋이다: ① 문서를 열고 쪽 크기를 알아 둔다, ② 확대 배율과 쪽 배치를 정한다, ③ 쪽 그림을 비동기로
/// 만들어 캐시한다. 엔진 호출은 `RhwpDocumentSession`(전용 큐 actor)이, 그리기는 `PageRenderer`가 하고 이
/// 클래스는 메인 액터에서 상태만 들고 있다. 순수 계산(배치·배율·캐시 정책)은 `RhwpViewer` 패키지에 있어
/// 단위 시험이 된다.
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

    @ObservationIgnored private var session: RhwpDocumentSession?
    @ObservationIgnored private let renderer = PageRenderer()
    @ObservationIgnored private var cache = LRUCache<RenderKey, CGImage>(costLimit: 384 * 1024 * 1024)
    @ObservationIgnored private var inFlight: [RenderKey: Task<CGImage?, Never>] = [:]
    @ObservationIgnored private var viewportWidth: Double = 0

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
            cache.removeAll()
            inFlight.removeAll()
            applyZoom(fitsWidth ? fittedZoom() ?? .actualSize : zoom)
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - 확대·축소

    /// 스크롤 영역의 너비(pt)가 바뀌었다. 너비 맞춤 중이면 배율을 다시 맞춘다.
    public func viewportWidthChanged(_ width: Double) {
        guard width > 0, width != viewportWidth else { return }
        viewportWidth = width
        if fitsWidth, let fitted = fittedZoom(), fitted != zoom { applyZoom(fitted) }
    }

    public func zoomIn() { setZoom(zoom.zoomedIn()) }
    public func zoomOut() { setZoom(zoom.zoomedOut()) }
    public func setZoom(_ newZoom: Zoom) {
        fitsWidth = false
        applyZoom(newZoom)
    }

    public func actualSize() { setZoom(.actualSize) }

    /// 쪽 너비를 창에 맞추고 창 크기가 바뀌어도 그 상태를 유지한다.
    public func fitWidth() {
        fitsWidth = true
        if let fitted = fittedZoom() { applyZoom(fitted) }
    }

    private func fittedZoom() -> Zoom? {
        guard viewportWidth > 0, let widest = pageSizes.map(\.width).max() else { return nil }
        return Zoom.fitWidth(availableWidth: viewportWidth - 2 * layout.margin, pageWidth: widest)
    }

    private func applyZoom(_ newZoom: Zoom) {
        zoom = newZoom
        layout = PageLayout(pageSizes: pageSizes, zoom: newZoom, spacing: layout.spacing, margin: layout.margin)
    }

    // MARK: - 쪽 그림

    /// 쪽 `page`를 px→비트맵 배율 `scale`로 그린 그림. 같은 요청이 진행 중이면 그 결과를 함께 기다린다.
    /// 취소되면 nil 이지만 시작한 그리기는 끝까지 가서 캐시에 남는다(스크롤로 잠깐 벗어난 쪽을 다시 그리지 않는다).
    public func image(page: Int, scale: Double) async -> CGImage? {
        let key = RenderKey(page: page, scale: scale)
        if let cached = cache.value(for: key) { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task { await self.produceImage(for: key) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    private func produceImage(for key: RenderKey) async -> CGImage? {
        guard let session else { return nil }
        do {
            let tree = try await session.layerTree(page: key.page)
            let renderer = renderer
            let scale = key.scale
            // 그리기는 메인 액터와 문서 큐 밖에서 한다. 레이어 트리와 렌더러 모두 Sendable 이다.
            let image = try await Task.detached(priority: .userInitiated) {
                try renderer.render(tree, scale: scale).image
            }.value
            cache.insert(image, cost: image.bytesPerRow * image.height, for: key)
            return image
        } catch {
            return nil
        }
    }

    /// 화면 배율과 현재 확대에 맞는 쪽 그림 배율.
    public func renderScale(page: Int, displayScale: Double) -> Double {
        guard pageSizes.indices.contains(page) else { return 1 }
        return RenderScalePolicy.scale(zoom: zoom, displayScale: displayScale, pageSize: pageSizes[page])
    }

    /// 사이드바 썸네일 한 장의 배율(px→비트맵). `width`는 썸네일의 화면 너비(pt)다.
    public func thumbnailScale(page: Int, width: Double, displayScale: Double) -> Double {
        guard pageSizes.indices.contains(page), pageSizes[page].width > 0 else { return 1 }
        return width * max(displayScale, 1) / pageSizes[page].width
    }
}

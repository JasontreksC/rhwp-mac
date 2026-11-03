import CoreGraphics
import Foundation
import RhwpKit
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

@MainActor
@Suite("ViewerModel")
struct ViewerModelTests {
    private func openedModel(_ name: String = "KTX.hwp") async throws -> ViewerModel {
        let model = ViewerModel()
        await model.open(data: try sampleData(name))
        return model
    }

    @Test("문서를 열면 쪽 크기와 배치가 쪽수만큼 만들어진다")
    func openBuildsLayout() async throws {
        let model = try await openedModel()
        #expect(model.phase == .ready)
        // 27쪽은 엔진 출력이 아니라 한컴 PDF(pdf/KTX-2022.pdf)의 쪽수다.
        #expect(model.pageCount == 27)
        #expect(model.layout.pageCount == 27)
        #expect(model.pageSizes.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    @Test("열기 전에는 불러오는 중이고, 손상된 파일은 실패 사유를 담는다")
    func loadingAndFailure() async throws {
        let model = ViewerModel()
        #expect(model.phase == .loading)
        await model.open(data: Data("not a hwp file".utf8))
        guard case let .failed(message) = model.phase else {
            Issue.record("실패 상태여야 함: \(model.phase)")
            return
        }
        #expect(!message.isEmpty)
        #expect(model.pageCount == 0)
    }

    @Test("너비 맞춤은 창 너비에서 좌우 여백을 뺀 값에 쪽 너비를 맞춘다")
    func fitWidthFollowsTheViewport() async throws {
        let model = try await openedModel()
        let pageWidth = try #require(model.pageSizes.map(\.width).max())
        model.viewportWidthChanged(1000)
        let expected = (1000 - 2 * model.layout.margin) / pageWidth
        #expect(abs(model.zoom.factor - expected) < 1e-9)
        #expect(model.fitsWidth)
        // 창을 넓히면 배율도 따라간다.
        model.viewportWidthChanged(1400)
        #expect(abs(model.zoom.factor - (1400 - 2 * model.layout.margin) / pageWidth) < 1e-9)
    }

    @Test("배율을 직접 정하면 너비 맞춤이 꺼지고 창 크기가 바뀌어도 유지된다")
    func manualZoomStopsFitting() async throws {
        let model = try await openedModel()
        model.viewportWidthChanged(1000)
        model.zoomIn()
        let chosen = model.zoom
        #expect(!model.fitsWidth)
        model.viewportWidthChanged(1600)
        #expect(model.zoom == chosen, "직접 정한 배율은 창 크기 변화로 바뀌지 않는다")
        // 너비에 맞춤을 다시 누르면 맞춤으로 돌아온다.
        model.fitWidth()
        #expect(model.fitsWidth && model.zoom != chosen)
    }

    @Test("배율이 바뀌면 배치의 쪽 크기가 같은 비율로 바뀐다")
    func layoutTracksZoom() async throws {
        let model = try await openedModel()
        model.setZoom(Zoom(1.0))
        let at100 = model.layout.frames[0].width
        model.setZoom(Zoom(2.0))
        #expect(abs(model.layout.frames[0].width - 2 * at100) < 1e-9)
        #expect(model.layout.zoom == Zoom(2.0))
    }

    @Test("쪽 그림은 쪽 크기대로 만들어지고 다시 요청하면 캐시에서 같은 그림이 온다")
    func imageIsCached() async throws {
        let model = try await openedModel()
        let size = model.pageSizes[0]
        let first = try #require(await model.image(page: 0, scale: 1))
        #expect(first.width == Int(size.width.rounded(.up)) && first.height == Int(size.height.rounded(.up)))
        let again = try #require(await model.image(page: 0, scale: 1))
        #expect(first === again, "같은 키는 새로 그리지 않고 캐시된 그림을 돌려준다")
        let other = try #require(await model.image(page: 0, scale: 0.5))
        #expect(other !== first && other.width < first.width, "배율이 다르면 다른 그림이다")
    }

    @Test("같은 그림을 동시에 요청하면 한 번만 그리고 같은 결과를 나눈다")
    func concurrentRequestsShareOneRender() async throws {
        let model = try await openedModel()
        async let a = model.image(page: 2, scale: 1)
        async let b = model.image(page: 2, scale: 1)
        async let c = model.image(page: 2, scale: 1)
        let images = await [a, b, c].compactMap { $0 }
        #expect(images.count == 3)
        #expect(images[0] === images[1] && images[1] === images[2], "진행 중인 요청을 함께 기다려야 한다")
    }

    @Test("범위 밖 쪽은 그림이 없다")
    func outOfRangePageHasNoImage() async throws {
        let model = try await openedModel()
        #expect(await model.image(page: 27, scale: 1) == nil)
        #expect(await model.image(page: -1, scale: 1) == nil)
    }

    @Test("그림 배율은 확대와 화면 배율에서 정해지고 썸네일은 너비에서 정해진다")
    func scales() async throws {
        let model = try await openedModel()
        model.setZoom(Zoom(1.0))
        #expect(model.renderScale(page: 0, displayScale: 2) == 2.0)
        #expect(model.renderScale(page: 99, displayScale: 2) == 1.0, "없는 쪽은 기본 1")
        // 너비 132pt 썸네일을 2배 화면에서 그리면 쪽 너비 793.7px 가 264px 로 줄어든다.
        let thumbnail = model.thumbnailScale(page: 0, width: 132, displayScale: 2)
        #expect(abs(thumbnail * model.pageSizes[0].width - 264) < 1e-6)
    }

    @Test("서로 다른 문서 모델은 독립적이다")
    func modelsAreIndependent() async throws {
        let ktx = try await openedModel("KTX.hwp")
        let table = try await openedModel("21868765_별표2_보건소_분장사무.hwp")
        // 보건소 문서는 한컴 PDF(samples/*.pdf)가 4쪽이다.
        #expect(table.pageCount == 4 && ktx.pageCount == 27)
        ktx.setZoom(Zoom(2.0))
        #expect(table.zoom != Zoom(2.0))
    }
}

import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender
import Testing

@Suite("PageRenderer — 손으로 만든 트리")
struct SyntheticTreeTests {
    private let red = (r: 255, g: 0, b: 0)
    private let blue = (r: 0, g: 0, b: 255)
    private let white = (r: 255, g: 255, b: 255)

    @Test("사각형은 bbox 안만 칠한다")
    func rectangleFillsOnlyItsBox() throws {
        let tree = try makeLeafTree(ops: [
            OpJSON.background(),
            OpJSON.rectangle(x: 10, y: 10, w: 30, h: 30, fill: "#ff0000"),
        ])
        let pixels = try Pixels(PageRenderer().render(tree, scale: 1).image)
        #expect(isNear(pixels.rgb(20, 20), red))
        #expect(isNear(pixels.rgb(5, 5), white))
        #expect(isNear(pixels.rgb(45, 20), white))
        #expect(isNear(pixels.rgb(20, 45), white))
    }

    @Test("배율은 비트맵 크기와 좌표에 곱해진다")
    func scaleMultipliesSizeAndCoordinates() throws {
        let tree = try makeLeafTree(ops: [
            OpJSON.background(),
            OpJSON.rectangle(x: 10, y: 10, w: 30, h: 30, fill: "#ff0000"),
        ])
        let page = try PageRenderer().render(tree, scale: 2)
        #expect(page.image.width == 200 && page.image.height == 200)
        let pixels = Pixels(page.image)
        #expect(isNear(pixels.rgb(40, 40), red), "쪽 좌표 (20,20)은 2배 비트맵의 (40,40)")
        #expect(isNear(pixels.rgb(90, 40), white), "쪽 좌표 (45,20)은 사각형 밖")
    }

    @Test("잘라내기 영역 밖은 자식이 그려지지 않는다")
    func clipHidesTheOutside() throws {
        let child = leaf(ops: [OpJSON.rectangle(x: 0, y: 0, w: 100, h: 100, fill: "#0000ff")])
        let clip = #"{"kind":"clipRect","bounds":{"x":0,"y":0,"width":100,"height":100},"clip":{"x":0,"y":0,"width":50,"height":100},"clipKind":"tableCell","child":\#(child)}"#
        let group = #"{"kind":"group","groupKind":{"kind":"generic"},"bounds":{"x":0,"y":0,"width":100,"height":100},"children":[\#(leaf(ops: [OpJSON.background()])),\#(clip)]}"#
        let pixels = try Pixels(PageRenderer().render(makeTree(group), scale: 1).image)
        #expect(isNear(pixels.rgb(25, 50), blue), "잘라내기 안쪽")
        #expect(isNear(pixels.rgb(75, 50), white), "잘라내기 바깥은 쪽 배경 그대로")
    }

    @Test("그라데이션 각도 90은 왼쪽에서 오른쪽, 0은 아래에서 위로 간다")
    func gradientAxisFollowsTheEngineConvention() throws {
        // 엔진 정본(linear_gradient_axis)의 규칙: 방향 = (sin θ, −cos θ). θ=90 → 좌→우, θ=0 → 아래→위.
        let leftToRight = try makeLeafTree(ops: [
            OpJSON.rectangle(x: 0, y: 0, w: 100, h: 100, fill: "#000000",
                             gradient: OpJSON.linearGradient(angle: 90, from: "#ff0000", to: "#0000ff")),
        ])
        let horizontal = try Pixels(PageRenderer().render(leftToRight, scale: 1).image)
        #expect(horizontal.rgb(2, 50).r > 230 && horizontal.rgb(2, 50).b < 25, "왼쪽 끝은 시작색(빨강)")
        #expect(horizontal.rgb(97, 50).b > 230 && horizontal.rgb(97, 50).r < 25, "오른쪽 끝은 끝색(파랑)")

        let bottomToTop = try makeLeafTree(ops: [
            OpJSON.rectangle(x: 0, y: 0, w: 100, h: 100, fill: "#000000",
                             gradient: OpJSON.linearGradient(angle: 0, from: "#ff0000", to: "#0000ff")),
        ])
        let vertical = try Pixels(PageRenderer().render(bottomToTop, scale: 1).image)
        #expect(vertical.rgb(50, 97).r > 230 && vertical.rgb(50, 97).b < 25, "아래 끝은 시작색(빨강)")
        #expect(vertical.rgb(50, 2).b > 230 && vertical.rgb(50, 2).r < 25, "위 끝은 끝색(파랑)")
    }

    @Test("선 전용 경로는 style이 아니라 lineStyle로 그린다")
    func pathLineStyleWins() throws {
        // style 은 테두리 없음(strokeColor null, 굵기 0)이고 lineStyle 이 검정 4px 이다.
        let path = #"""
        {"type":"path","bbox":{"x":10,"y":48,"width":80,"height":4},
         "commands":[{"type":"moveTo","x":10,"y":50},{"type":"lineTo","x":90,"y":50}],
         "style":\#(OpJSON.style(fill: nil)),"lineStyle":{"color":"#000000","width":4,"dash":"solid"}}
        """#
        let tree = try makeLeafTree(ops: [OpJSON.background(), path])
        let pixels = try Pixels(PageRenderer().render(tree, scale: 1).image)
        #expect(isNear(pixels.rgb(50, 50), (0, 0, 0)), "선 위")
        #expect(isNear(pixels.rgb(50, 60), white), "선 밖")
    }

    @Test("글자는 엔진이 준 위치에 놓이고 렌더러가 다시 배치하지 않는다")
    func textFollowsEnginePositions() throws {
        func inkColumns(positions: [Double]) throws -> ClosedRange<Int> {
            let run = OpJSON.textRun("I", font: "Helvetica", size: 30, originX: 10, baseline: 60, positions: positions)
            let pixels = try Pixels(PageRenderer().render(makeLeafTree(ops: [OpJSON.background(), run]), scale: 1).image)
            return try #require(pixels.inkColumns(), "글자가 그려져야 함")
        }
        let near = try inkColumns(positions: [0, 10])
        let far = try inkColumns(positions: [50, 60])
        // 같은 글자를 run 원점에서 50px 더 떨어진 위치에 놓았으니 잉크도 50px 옮겨진다.
        #expect(abs((far.lowerBound - near.lowerBound) - 50) <= 2, "\(near) → \(far)")
    }

    @Test("모르는 op는 건너뛰고 이름으로 집계한다")
    func unknownOpsAreReported() throws {
        let tree = try makeLeafTree(ops: [
            OpJSON.background(),
            #"{"type":"charOverlap","bbox":{"x":0,"y":0,"width":1,"height":1}}"#,
            #"{"type":"charOverlap","bbox":{"x":0,"y":0,"width":1,"height":1}}"#,
            #"{"type":"somethingNew"}"#,
        ])
        let report = try PageRenderer().render(tree, scale: 1).report
        #expect(report.skipped["op:charOverlap"] == 2)
        #expect(report.skipped["op:somethingNew"] == 1)
        #expect(report.rendered["op:pageBackground"] == 1)
    }

    @Test("문서에 없는 글꼴은 대체 사실을 보고한다")
    func fontSubstitutionIsReported() throws {
        let run = OpJSON.textRun("가", font: "RHWP-NoSuchFont", size: 20, originX: 10, baseline: 50, positions: [0, 20])
        let report = try PageRenderer().render(makeLeafTree(ops: [run]), scale: 1).report
        #expect(report.fontSubstitutions["RHWP-NoSuchFont"] != nil)
    }

    @Test("쪽 크기가 비정상이면 비트맵을 만들지 않는다", arguments: [0, -5])
    func invalidPageSize(width: Int) throws {
        let tree = try makeLeafTree(ops: [], width: width, height: 100)
        #expect(throws: RenderError.invalidPageSize(width: Double(width), height: 100)) {
            _ = try PageRenderer().render(tree, scale: 1)
        }
    }

    @Test("너무 큰 쪽은 거부한다")
    func hugePageIsRejected() throws {
        let tree = try makeLeafTree(ops: [], width: 20000, height: 100)
        #expect(throws: RenderError.self) { _ = try PageRenderer().render(tree, scale: 1) }
    }
}

@Suite("PageRenderer — 실제 문서")
struct RealDocumentTests {
    @Test("모든 op가 그렸거나 건너뛴 쪽에 한 번씩 집계된다", arguments: [
        ("KTX.hwp", 0), ("KTX.hwp", 5), ("21868765_별표2_보건소_분장사무.hwp", 0),
        ("2025년 기부·답례품 실적 지자체 보고서_양식.hwpx", 3), ("hwp3-curve.hwp", 0),
    ])
    func everyOpIsAccountedFor(name: String, page: Int) async throws {
        let session = try await Fixtures.openSession(name)
        let tree = try await session.layerTree(page: page)
        let report = try PageRenderer().render(tree, scale: 1).report
        // 트리의 op 수는 렌더러와 무관하게 센다. 빠지거나 두 번 세어지면 합이 어긋난다.
        #expect(report.renderedOpCount + report.skippedOpCount == countOps(tree.root), "\(name) \(page)쪽")
        #expect(report.rendered["op:pageBackground"] == 1)
    }

    @Test("KTX 첫 쪽은 비어 있지 않고 쪽 크기대로 그려진다")
    func ktxFirstPageHasInk() async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        let tree = try await session.layerTree(page: 0)
        let page = try PageRenderer().render(tree, scale: 1)
        #expect(page.image.width == Int(tree.pageWidth.rounded(.up)))
        #expect(page.image.height == Int(tree.pageHeight.rounded(.up)))
        #expect(Pixels(page.image).inkColumns() != nil, "글자와 도형이 하나도 그려지지 않음")
        #expect((page.report.rendered["op:textRun"] ?? 0) > 0)
    }

    @Test("같은 쪽을 여러 작업이 동시에 그려도 결과가 같다")
    func concurrentRendersAgree() async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        let tree = try await session.layerTree(page: 1)
        let renderer = PageRenderer()
        let reference = try Pixels(renderer.render(tree, scale: 1).image)
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    let pixels = try Pixels(renderer.render(tree, scale: 1).image)
                    return pixels.width == reference.width && pixels.height == reference.height
                        && pixels.rgb(300, 300) == reference.rgb(300, 300) && pixels.inkColumns() == reference.inkColumns()
                }
            }
            for try await same in group { #expect(same) }
        }
    }

    @Test("PNG로 인코딩된다")
    func pngEncoding() async throws {
        let session = try await Fixtures.openSession("hwp3-curve.hwp")
        let tree = try await session.layerTree(page: 0)
        let page = try PageRenderer().render(tree, scale: 1)
        let data = try #require(page.pngData())
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]), "PNG 시그니처")
    }
}

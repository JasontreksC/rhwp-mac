import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender
import Testing

/// 실제 문서 쪽에서 4단계에 추가한 op들이 **그려지고 건너뛰어지지 않는지** 본다. 대상 쪽은 엔진 출력의 op 종류를
/// 훑어 고른 것이다. 픽셀 정확도는 위의 손으로 만든 시험과 한컴 PDF 대조(`fidelity-sweep.py`)가 맡는다.
private struct OpCase: Sendable, CustomTestStringConvertible {
    let file: String
    let page: Int
    let opName: String
    var testDescription: String { "\(file) \(page + 1)쪽의 \(opName)" }
}

/// 트리의 모든 잎 op(렌더러의 집계와 독립적인 기준).
private func allOps(_ node: LayerNode) -> [PaintOp] {
    switch node.content {
    case let .group(_, children): children.flatMap(allOps)
    case let .clip(_, _, child): allOps(child)
    case let .leaf(ops): ops
    case .unsupported: []
    }
}

@Suite("실제 문서의 op")
struct RealDocumentOpTests {
    private static let cases = [
        OpCase(file: "eq-01.hwp", page: 0, opName: "op:equation"),
        OpCase(file: "exam_math.hwp", page: 0, opName: "op:equation"),
        OpCase(file: "2022년 국립국어원 업무계획.hwp", page: 1, opName: "op:tabLeader"),
        OpCase(file: "143E433F503322BD33.hwp", page: 0, opName: "op:textDecoration"),
        OpCase(file: "bitmap.hwp", page: 0, opName: "op:rawSvg"),
        OpCase(file: "form-01.hwp", page: 0, opName: "op:formObject"),
        OpCase(file: "2010-01-06.hwp", page: 0, opName: "op:footnoteMarker"),
    ]

    @Test("새 op는 실제 문서에서 그려지고 집계에서 빠지지 않는다", arguments: cases)
    fileprivate func newOpsAreDrawn(_ testCase: OpCase) async throws {
        let session = try await Fixtures.openSession(testCase.file)
        let tree = try await session.layerTree(page: testCase.page)
        let report = try PageRenderer().render(tree, scale: 1).report

        // 입력에 그 op가 실제로 있어야 한다(조용히 0건을 검사하는 시험이 되지 않도록).
        let typeName = String(testCase.opName.dropFirst(3))
        let present = allOps(tree.root).filter { $0.typeName == typeName }.count
        try #require(present > 0, "\(testCase.testDescription): 입력에 op가 없다")

        #expect(report.rendered[testCase.opName, default: 0] == present, "\(report.rendered)")
        #expect(report.skipped.keys.filter { $0.contains(typeName) }.isEmpty, "\(report.skipped)")
    }

    @Test("SVG로 감싼 그림이 든 문서도 건너뛴 op가 없다")
    func svgWrappedImageIsDrawn() async throws {
        let session = try await Fixtures.openSession("bitmap.hwp")
        let report = try PageRenderer().render(try await session.layerTree(page: 0), scale: 1).report
        #expect(report.skipped.isEmpty, "\(report.skipped)")
        #expect(report.rendered["svg:image(svg)"] == 1)
    }
}

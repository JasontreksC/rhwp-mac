import Foundation
import Testing

@testable import RhwpKit

@Suite("레이어 트리 디코딩")
struct LayerTreeDecodingTests {
    // MARK: - 실제 문서

    @Test("KTX 1쪽은 A4 크기이고 배경이 가장 먼저 그려진다")
    func ktxFirstPageBasics() async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        let tree = try await session.layerTree(page: 0)

        // A4(210×297mm)를 96dpi px로 환산한 값: 793.70 × 1122.52. 엔진 출력이 아니라 규격에서 정한 값이다.
        #expect(abs(tree.pageWidth - 210 / 25.4 * 96) < 0.1)
        #expect(abs(tree.pageHeight - 297 / 25.4 * 96) < 0.1)
        #expect(tree.schemaVersion == PageLayerTree.supportedSchemaVersion)

        // 그리는 순서는 배열 순서다. 배경이 맨 앞이 아니면 뒤의 모든 내용을 덮는다.
        guard case .pageBackground? = tree.root.allOps.first else {
            Issue.record("첫 op가 pageBackground가 아님: \(String(describing: tree.root.allOps.first?.typeName))")
            return
        }
    }

    /// 디코더가 op를 하나도 잃거나 더하지 않는지, 같은 JSON을 타입 없이 읽은 결과와 대조한다.
    /// (타입 모델 디코딩과 독립된 경로인 JSONSerialization으로 센다.)
    @Test("모든 쪽에서 op 종류별 개수가 원본 JSON과 같다")
    func decoderPreservesEveryOp() async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        for page in 0..<27 {
            let json = try await session.layerTreeJSON(page: page)
            let tree = try NativeEnvelope.decodeLayerTree(from: json)

            let envelope = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
            let layerTree = try #require(envelope["layerTree"] as? [String: Any])
            var expected: [String: Int] = [:]
            Self.countOps(in: try #require(layerTree["root"] as? [String: Any]), into: &expected)

            var actual: [String: Int] = [:]
            for op in tree.root.allOps { actual[op.typeName, default: 0] += 1 }

            #expect(actual == expected, "쪽 \(page): 디코딩된 op 개수가 원본 JSON과 다름")
        }
    }

    private static func countOps(in node: [String: Any], into counts: inout [String: Int]) {
        switch node["kind"] as? String {
        case "group":
            for child in node["children"] as? [[String: Any]] ?? [] { countOps(in: child, into: &counts) }
        case "clipRect":
            if let child = node["child"] as? [String: Any] { countOps(in: child, into: &counts) }
        case "leaf":
            for op in node["ops"] as? [[String: Any]] ?? [] {
                counts[op["type"] as? String ?? "?", default: 0] += 1
            }
        default:
            break
        }
    }

    /// 렌더러가 기대는 계약: 글자별 위치 배열은 (스칼라 수 + 1)개다.
    @Test("글자 run의 위치 배열 길이는 글자 수 + 1이다")
    func textRunPositionsContract() async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        var checked = 0
        for page in 0..<27 {
            for case let .textRun(run) in try await session.layerTree(page: page).root.allOps {
                let scalars = run.renderedText.unicodeScalars.count
                #expect(
                    run.renderedPositions.count == scalars + 1 || scalars == 0,
                    "쪽 \(page) '\(run.renderedText.prefix(10))': 위치 \(run.renderedPositions.count)개, 글자 \(scalars)개"
                )
                checked += 1
            }
        }
        #expect(checked > 100, "검사한 글자 run이 너무 적음: \(checked)")
    }

    @Test(
        "여러 형식·문서의 쪽이 모두 디코딩된다",
        arguments: [
            ("KTX.hwp", 27),
            ("21868765_별표2_보건소_분장사무.hwp", 4),   // 표·선이 많은 문서
            ("2022년 국립국어원 업무계획.hwp", 35),
            ("2025년 기부·답례품 실적 지자체 보고서_양식.hwpx", nil),   // HWPX
            ("2025 행정업무운영 편람(최종).hwpx", 12),   // 큰 HWPX의 앞부분만
        ] as [(String, Int?)]
    )
    func everyPageDecodes(name: String, limit: Int?) async throws {
        let session = try await Fixtures.openSession(name)
        let pageCount = try await session.pageCount()
        let pages = min(pageCount, limit ?? pageCount)
        #expect(pages > 0)

        var opKinds = Set<String>()
        for page in 0..<pages {
            // 디코딩이 던지면 어느 필드에서 실패했는지 malformedResponse 메시지에 경로가 담긴다.
            let tree = try await session.layerTree(page: page)
            for op in tree.root.allOps { opKinds.insert(op.typeName) }
        }
        // 어떤 문서든 최소한 배경과 글자는 있어야 한다. 빈 결과로 통과하지 않게 한다.
        #expect(opKinds.contains("pageBackground"))
        #expect(opKinds.contains("textRun"))
    }

    /// 샘플 전체를 훑었을 때 `ellipse`는 hwp3-curve.hwp, `path`는 KTX 2쪽에서 처음 나왔다.
    /// 합성 JSON이 아니라 실제 문서의 값으로 두 모델의 필드를 확인한다.
    @Test("실제 문서의 ellipse와 path가 의미 있는 값으로 디코딩된다")
    func ellipseAndPathFromRealDocuments() async throws {
        let curve = try await Fixtures.openSession("hwp3-curve.hwp").layerTree(page: 0)
        let ellipses = curve.root.allOps.compactMap { op -> EllipseOp? in
            if case let .ellipse(ellipse) = op { return ellipse } else { return nil }
        }
        let ellipse = try #require(ellipses.first, "hwp3-curve.hwp 1쪽에 ellipse가 없음")
        #expect(ellipse.bbox.width > 0 && ellipse.bbox.height > 0)
        #expect(ellipse.style.fillColor != nil || ellipse.style.strokeColor != nil, "칠도 테두리도 없는 타원")

        let ktx = try await Fixtures.openSession("KTX.hwp").layerTree(page: 1)
        let paths = ktx.root.allOps.compactMap { op -> PathOp? in
            if case let .path(path) = op { return path } else { return nil }
        }
        let path = try #require(paths.first, "KTX 2쪽에 path가 없음")
        // 경로는 항상 이동으로 시작하고, 모르는 명령이 섞여 있으면 안 된다.
        guard case .moveTo? = path.commands.first else {
            Issue.record("path가 moveTo로 시작하지 않음: \(String(describing: path.commands.first))")
            return
        }
        #expect(!path.commands.contains { if case .unsupported = $0 { true } else { false } })
    }

    @Test("KTX의 그라데이션 막대는 좌→우 선형이다(한컴 PDF와 같은 방향)")
    func ktxGradientIsHorizontal() async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        let tree = try await session.layerTree(page: 0)
        let gradientRects = tree.root.allOps.compactMap { op -> RectangleOp? in
            if case let .rectangle(rect) = op, rect.gradient != nil { return rect }
            return nil
        }
        let rect = try #require(gradientRects.first, "그라데이션 사각형이 없음")
        let gradient = try #require(rect.gradient)
        let axis = gradient.linearAxis(in: rect.bbox)

        // pdf/KTX-2022.pdf에서 이 막대는 왼쪽에서 오른쪽으로 색이 변한다.
        #expect(axis.end.x > axis.start.x)
        #expect(abs(axis.end.y - axis.start.y) < 1e-6)
        #expect(gradient.colors.count == gradient.positions.count)
        #expect(gradient.colors.count >= 2)
    }

    // MARK: - 합성 입력(스키마 계약)

    @Test("그라데이션 각도 규칙: 0은 아래→위, 90은 좌→우")
    func gradientAxisRule() {
        let bounds = LayerRect(x: 10, y: 20, width: 100, height: 40)
        func gradient(angle: Int) -> Gradient {
            Gradient(gradientType: 1, angle: angle, centerX: 0, centerY: 0, colors: [], positions: [])
        }

        // 각도 0: 방향 (0, -1) → 아래에서 위로. 중심 (60, 40)에서 높이의 절반(20)만큼 벌린다.
        let up = gradient(angle: 0).linearAxis(in: bounds)
        #expect(abs(up.start.x - 60) < 1e-9 && abs(up.start.y - 60) < 1e-9)
        #expect(abs(up.end.x - 60) < 1e-9 && abs(up.end.y - 20) < 1e-9)

        // 각도 90: 방향 (1, 0) → 좌에서 우로. 폭의 절반(50)만큼 벌린다.
        let right = gradient(angle: 90).linearAxis(in: bounds)
        #expect(abs(right.start.x - 10) < 1e-9 && abs(right.start.y - 40) < 1e-9)
        #expect(abs(right.end.x - 110) < 1e-9 && abs(right.end.y - 40) < 1e-9)
    }

    @Test("색은 #rrggbb만 받는다")
    func colorParsing() {
        #expect(LayerColor(cssHex: "#ff0080") == LayerColor(red: 255, green: 0, blue: 128))
        #expect(LayerColor(cssHex: "#FF0080") == LayerColor(red: 255, green: 0, blue: 128))
        for bad in ["ff0080", "#ff008", "#ff00800", "#gg0000", "rgb(1,2,3)", "", "#"] {
            #expect(LayerColor(cssHex: bad) == nil, "받아들이면 안 되는 색: \(bad)")
        }
    }

    @Test("모르는 op와 노드는 디코딩을 깨지 않고 보존된다")
    func unknownKindsSurvive() throws {
        let json = Self.envelope(root: """
        {"bounds":{"x":0,"y":0,"width":10,"height":10},"kind":"leaf","ops":[
          {"type":"charOverlap","bbox":{"x":0,"y":0,"width":1,"height":1}},
          {"type":"futureOp"}
        ]}
        """)
        let tree = try NativeEnvelope.decodeLayerTree(from: Data(json.utf8))
        #expect(tree.root.allOps == [.unsupported(type: "charOverlap"), .unsupported(type: "futureOp")])

        let futureNode = try NativeEnvelope.decodeLayerTree(from: Data(Self.envelope(root: """
        {"bounds":{"x":0,"y":0,"width":1,"height":1},"kind":"hologram"}
        """).utf8))
        #expect(futureNode.root.content == .unsupported(kind: "hologram"))
    }

    @Test("오류 봉투는 native 오류로 전달된다")
    func errorEnvelope() {
        let json = Data(#"{"ok":false,"error":"엔진이 말한 오류"}"#.utf8)
        #expect(throws: RhwpError.native("엔진이 말한 오류")) {
            _ = try NativeEnvelope.decodeLayerTree(from: json)
        }
    }

    @Test("약속과 다른 응답은 필드 경로가 담긴 malformedResponse다")
    func malformedResponses() {
        func message(for json: String) -> String? {
            do {
                _ = try NativeEnvelope.decodeLayerTree(from: Data(json.utf8))
                return nil
            } catch let RhwpError.malformedResponse(detail) {
                return detail
            } catch {
                return "다른 오류: \(error)"
            }
        }

        // JSON이 아님
        #expect(message(for: "garbage") != nil)
        // ok인데 layerTree 없음
        #expect(message(for: #"{"ok":true}"#)?.contains("layerTree") == true)
        // 다른 스키마 주 버전은 해석하지 않는다
        let futureSchema = Self.envelope(root: Self.emptyLeaf, schemaVersion: 2)
        #expect(message(for: futureSchema)?.contains("스키마") == true)
        // 좌표계가 바뀌면 잘못 그리는 대신 실패한다
        let otherCoordinates = Self.envelope(root: Self.emptyLeaf, coordinateSystem: "page-bottom-left-y-up")
        #expect(message(for: otherCoordinates)?.contains("좌표계") == true)
        // 색 형식이 다르면 어느 필드인지 알려준다
        let badColor = Self.envelope(root: """
        {"bounds":{"x":0,"y":0,"width":1,"height":1},"kind":"leaf","ops":[
          {"type":"pageBackground","bbox":{"x":0,"y":0,"width":1,"height":1},"backgroundColor":"red"}]}
        """)
        #expect(message(for: badColor)?.contains("backgroundColor") == true)
    }

    // MARK: - 합성 JSON 도우미

    private static let emptyLeaf = #"{"bounds":{"x":0,"y":0,"width":1,"height":1},"kind":"leaf","ops":[]}"#

    private static func envelope(
        root: String,
        schemaVersion: Int = 1,
        coordinateSystem: String = "page-top-left-y-down"
    ) -> String {
        """
        {"ok":true,"pageCount":1,"page":0,"layerTree":{
          "schemaVersion":\(schemaVersion),"schemaMinorVersion":0,"unit":"px",
          "coordinateSystem":"\(coordinateSystem)","pageWidth":100,"pageHeight":100,"root":\(root)}}
        """
    }
}

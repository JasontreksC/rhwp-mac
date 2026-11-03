import Foundation
import RhwpKit
import Testing

/// 4단계에서 모델링한 op들의 디코딩. 입력은 엔진 직렬화기(`src/paint/json.rs`)가 내는 모양을 손으로 옮긴 것이다.
@Suite("새 op 디코딩")
struct NewOpDecodingTests {
    private func decode(_ json: String) throws -> PaintOp {
        try JSONDecoder().decode(PaintOp.self, from: Data(json.utf8))
    }

    private let box = #""bbox":{"x":10,"y":20,"width":100,"height":30}"#

    @Test("수식은 조각과 고유 크기를 읽고 엔진의 배율 규칙을 따른다")
    func equation() throws {
        func equation(height: Double) throws -> EquationOp {
            let op = try decode("""
            {"type":"equation","bbox":{"x":10,"y":20,"width":100,"height":\(height)},"svgContent":"<line/>",
             "color":"#112233","fontSize":20,
             "layoutBox":{"x":0,"y":0,"width":50,"height":40,"baseline":10,"kind":{"type":"row"}}}
            """)
            guard case let .equation(equation) = op else { Issue.record("equation이 아님: \(op)"); throw CancellationError() }
            return equation
        }
        let normal = try equation(height: 30)
        #expect(normal.layoutWidth == 50 && normal.layoutHeight == 40)
        #expect(normal.color == LayerColor(red: 0x11, green: 0x22, blue: 0x33))
        // 가로는 저장 상자 너비에 항상 맞춘다: 100 / 50.
        #expect(normal.contentScale.x == 2)
        // 상자 높이(30)가 글자 크기(20)보다 크면 일반 수식이다: 줄 여백이 있으니 세로는 늘이지 않는다.
        #expect(normal.contentScale.y == 1)
        // 글자 크기(20)보다 낮은 압축 프레임은 고유 높이(40)에 맞춘다: 8 / 40.
        #expect(try equation(height: 8).contentScale.y == 0.2)
    }

    @Test("글자 장식은 종류·기준선·글자 위치를 읽는다")
    func textDecoration() throws {
        let op = try decode("""
        {"type":"textDecoration",\(box),"decoration":{"kind":"emphasisDot","baseline":14.5,"rotation":0,
         "isVertical":false,"fontSize":20,"ratio":0.9,"color":"#ff0000","shape":0,"underline":"none",
         "emphasisDot":2,"positions":[0,10.5,21],"positionsComplete":true}}
        """)
        guard case let .textDecoration(decoration) = op else { Issue.record("textDecoration이 아님"); return }
        #expect(decoration.kind == .emphasisDot)
        #expect(decoration.baseline == 14.5 && decoration.fontSize == 20 && decoration.ratio == 0.9)
        #expect(decoration.emphasisDot == 2 && decoration.underline == .none)
        #expect(decoration.positions == [0, 10.5, 21])
        #expect(decoration.color == LayerColor(red: 255, green: 0, blue: 0))
    }

    @Test("탭 리더는 줄의 탭마다 시작·끝·채움 모양을 읽는다")
    func tabLeader() throws {
        let op = try decode("""
        {"type":"tabLeader",\(box),"leaders":[{"startX":5,"endX":60.5,"fillType":3},{"startX":70,"endX":90,"fillType":1}],
         "leadersComplete":true,"color":"#000000","fontSize":16,"baseline":12,"rotation":0,"isVertical":false}
        """)
        guard case let .tabLeader(leader) = op else { Issue.record("tabLeader가 아님"); return }
        #expect(leader.leaders.map(\.fillType) == [3, 1])
        #expect(leader.leaders[0].startX == 5 && leader.leaders[0].endX == 60.5)
        #expect(leader.fontSize == 16 && leader.baseline == 12)
    }

    @Test("각주 표식·자리 표시·원본 SVG")
    func smallOps() throws {
        guard case let .footnoteMarker(marker) = try decode(
            ##"{"type":"footnoteMarker",\##(box),"text":"3","fontFamily":"함초롬바탕","fontSize":7.7,"color":"#000000"}"##
        ) else { Issue.record("footnoteMarker가 아님"); return }
        #expect(marker.text == "3" && marker.fontFamily == "함초롬바탕" && marker.fontSize == 7.7)

        guard case let .placeholder(ole) = try decode(
            ##"{"type":"placeholder",\##(box),"kind":"ole","fillColor":"#eeeeff","strokeColor":"#333333","label":"OLE 개체"}"##
        ) else { Issue.record("placeholder가 아님"); return }
        #expect(ole.kind == .ole && ole.label == "OLE 개체")
        guard case let .placeholder(missing) = try decode(
            ##"{"type":"placeholder",\##(box),"kind":"missingPicture","fillColor":"#ffffff","strokeColor":"#999999","label":""}"##
        ) else { Issue.record("placeholder가 아님"); return }
        #expect(missing.kind == .missingPicture)

        guard case let .rawSvg(raw) = try decode(##"{"type":"rawSvg",\##(box),"svg":"<rect width=\"1\"/>"}"##)
        else { Issue.record("rawSvg가 아님"); return }
        #expect(raw.svg == #"<rect width="1"/>"#)
    }

    @Test("양식 개체는 도형 조각과 라벨을 읽고 모르는 조각은 보존한다")
    func formObject() throws {
        let op = try decode("""
        {"type":"formObject",\(box),"formType":"pushButton","caption":"확인","text":"확인","foreColor":"#000000",
         "backColor":"#c0c0c0","value":0,"enabled":true,
         "drawing":{"primitives":[
           {"kind":"rect","bbox":{"x":1,"y":2,"width":3,"height":4},"color":"#fafafa"},
           {"kind":"circle","x":5,"y":6,"radius":7,"color":"#404040"},
           {"kind":"polyline","points":[[0,0],[1,2],[3,4]],"color":"#000000","width":1.5,"closed":true},
           {"kind":"hologram"}],
          "label":{"text":"확인","x":4,"baseline":20,"fontFamily":"굴림","fontSize":12,"bold":true,"italic":false,"color":"#000000"}}}
        """)
        guard case let .formObject(form) = op else { Issue.record("formObject가 아님"); return }
        #expect(form.formType == "pushButton")
        #expect(form.primitives.count == 4)
        #expect(form.primitives[0] == .rect(LayerRect(x: 1, y: 2, width: 3, height: 4), color: LayerColor(red: 0xfa, green: 0xfa, blue: 0xfa)))
        #expect(form.primitives[1] == .circle(x: 5, y: 6, radius: 7, color: LayerColor(red: 0x40, green: 0x40, blue: 0x40)))
        #expect(form.primitives[2] == .polyline(
            points: [LayerPoint(x: 0, y: 0), LayerPoint(x: 1, y: 2), LayerPoint(x: 3, y: 4)],
            color: LayerColor(red: 0, green: 0, blue: 0), width: 1.5, closed: true
        ))
        #expect(form.primitives[3] == .unsupported(kind: "hologram"))
        #expect(form.label?.text == "확인" && form.label?.bold == true && form.label?.baseline == 20)
    }

    @Test("그림은 잘라내기 기준 크기·효과·밝기·대비를 읽는다")
    func imageExtras() throws {
        guard case let .image(image) = try decode("""
        {"type":"image",\(box),"mime":"image/png","fillMode":"zoom","crop":{"left":1,"top":2,"right":3,"bottom":4},
         "originalSizeHu":[7500,3750],"effect":"grayScale","brightness":-10,"contrast":20,"opacity":0.5}
        """) else { Issue.record("image가 아님"); return }
        #expect(image.originalSizeHU == [7500, 3750])
        #expect(image.effect == "grayScale" && image.brightness == -10 && image.contrast == 20)
        #expect(image.opacity == 0.5)

        // 효과·밝기·대비가 없으면 기본값이다(엔진은 `realPic`과 0을 항상 싣지만 옛 입력에 없을 수 있다).
        guard case let .image(plain) = try decode(##"{"type":"image",\##(box)}"##) else { Issue.record("image가 아님"); return }
        #expect(plain.effect == "realPic" && plain.brightness == 0 && plain.contrast == 0 && plain.originalSizeHU == nil)
    }
}

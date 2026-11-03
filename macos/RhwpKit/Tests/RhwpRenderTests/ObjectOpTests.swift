import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender
import Testing

/// 렌더 시험의 공통 보조. 기대 픽셀은 엔진 출력이 아니라 손으로 계산한 값이다.
func renderOps(_ ops: [String], size: Int = 100, scale: Double = 1) throws -> (pixels: Pixels, report: RenderReport) {
    let tree = try makeLeafTree(ops: [OpJSON.background(size: size)] + ops, width: size, height: size)
    let page = try PageRenderer().render(tree, scale: scale)
    return (Pixels(page.image), page.report)
}

/// SVG 조각을 담은 `rawSvg` op. JSON 이스케이프는 직렬화기에 맡겨 시험 문자열에 `\"` 가 섞이지 않게 한다.
func rawSvgOp(_ svg: String) throws -> String {
    let object: [String: Any] = ["type": "rawSvg", "bbox": ["x": 0, "y": 0, "width": 100, "height": 100], "svg": svg]
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

func isWhite(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r == 255 && c.g == 255 && c.b == 255 }

extension Pixels {
    /// 사각형(쪽 좌표, 끝 제외) 안에서 흰색이 아닌 픽셀 수.
    func inkCount(x: Range<Int>, y: Range<Int>) -> Int {
        var count = 0
        for row in y { for column in x where !isWhite(rgb(column, row)) { count += 1 } }
        return count
    }
}

@Suite("수식·원본 SVG·각주 표식·자리 표시·양식 개체")
struct ObjectOpTests {
    private let red = (r: 255, g: 0, b: 0)
    private let blue = (r: 0, g: 0, b: 255)
    private let green = (r: 0, g: 255, b: 0)

    @Test("수식 조각은 bbox 왼쪽 위에 놓이고 가로는 저장 상자 너비에 맞춰 늘어난다")
    func equationPlacementAndScale() throws {
        // 조각 안의 선은 (0,10)~(20,10), 굵기 2. 고유 크기 20×20, 저장 상자 (10,10) 40×20 → 가로 2배, 세로 1배.
        let object: [String: Any] = [
            "type": "equation", "bbox": ["x": 10, "y": 10, "width": 40, "height": 20],
            "svgContent": ##"<line x1="0" y1="10" x2="20" y2="10" stroke="#ff0000" stroke-width="2"/>"##,
            "color": "#ff0000", "fontSize": 10,
            "layoutBox": ["x": 0, "y": 0, "width": 20, "height": 20, "baseline": 10, "kind": ["type": "row"]],
        ]
        let equation = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let (pixels, report) = try renderOps([equation])
        // 선은 쪽 좌표 y=20(= 10 + 10)을 따라 x 10…50에 놓인다.
        #expect(isNear(pixels.rgb(12, 20), red), "왼쪽 끝 근처")
        #expect(isNear(pixels.rgb(45, 20), red), "2배로 늘어난 오른쪽 — 늘어나지 않았다면 x=30에서 끝난다")
        #expect(isWhite(pixels.rgb(55, 20)), "상자 밖")
        #expect(isWhite(pixels.rgb(30, 30)), "선 아래")
        #expect(report.rendered["op:equation"] == 1)
        #expect(report.skipped.isEmpty, "\(report.skipped)")
    }

    @Test("원본 SVG는 쪽 좌표 그대로 그린다")
    func rawSvgUsesPageCoordinates() throws {
        let raw = try rawSvgOp(##"<rect x="20" y="30" width="30" height="20" fill="#ff0000"/>"##)
        let (pixels, report) = try renderOps([raw])
        #expect(isNear(pixels.rgb(30, 40), red))
        #expect(isWhite(pixels.rgb(60, 40)))
        #expect(report.rendered["svg:rect"] == 1)
    }

    @Test("SVG 조각 안의 SVG 그림도 그린다(XML 파서 재진입으로 죽지 않는다)")
    func svgImageInsideRawSvg() throws {
        let inner = ##"<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" fill="#00ff00"/><rect width="5" height="10" fill="#ff0000"/></svg>"##
        let uri = "data:image/svg+xml;base64," + Data(inner.utf8).base64EncodedString()
        let raw = try rawSvgOp(#"<image x="10" y="10" width="40" height="40" xlink:href="\#(uri)"/>"#)
        let (pixels, report) = try renderOps([raw])
        #expect(isNear(pixels.rgb(15, 30), red), "viewBox 왼쪽 절반")
        #expect(isNear(pixels.rgb(45, 30), green), "viewBox 오른쪽 절반")
        #expect(isWhite(pixels.rgb(60, 30)))
        #expect(report.skipped.isEmpty, "\(report.skipped)")
    }

    @Test("SVG 호는 정확한 호로 그려진다(반원은 위로 볼록, 중심과 아래는 비어 있다)")
    func svgArcIsExact() throws {
        // (10,50)에서 (90,50)까지 반지름 40, sweep=1: 화면(y 아래)에서 시계 방향 → 위로 볼록한 반원.
        func render(radius: Int) throws -> Pixels {
            let raw = try rawSvgOp(##"<path d="M10,50 A\##(radius),\##(radius) 0 0 1 90,50" fill="none" stroke="#000000" stroke-width="2"/>"##)
            return try renderOps([raw]).pixels
        }
        for radius in [40, 10] {  // 10은 너무 작아 규격(F.6.6)대로 40으로 키워진다.
            let pixels = try render(radius: radius)
            #expect(!isWhite(pixels.rgb(50, 10)), "반지름 \(radius): 호의 꼭대기")
            #expect(isWhite(pixels.rgb(50, 50)), "반지름 \(radius): 중심")
            #expect(isWhite(pixels.rgb(50, 90)), "반지름 \(radius): 반대편에는 호가 없다")
        }
    }

    @Test("경로 op의 arcTo도 같은 호다")
    func pathOpArc() throws {
        let path = #"""
        {"type":"path","bbox":{"x":10,"y":10,"width":80,"height":40},
         "commands":[{"type":"moveTo","x":10,"y":50},{"type":"arcTo","rx":40,"ry":40,"rotation":0,"largeArc":false,"sweep":true,"x":90,"y":50}],
         "style":{"fillColor":null,"strokeColor":"#000000","strokeWidth":2,"strokeDash":"solid","opacity":1}}
        """#
        let (pixels, report) = try renderOps([path])
        #expect(!isWhite(pixels.rgb(50, 10)), "호의 꼭대기")
        #expect(isWhite(pixels.rgb(50, 50)), "중심")
        #expect(report.skipped["path:arcTo(approximated)"] == nil, "더 이상 직선으로 근사하지 않는다")
    }

    @Test("tspan의 dx는 앞 조각이 끝난 자리에서 이어진다")
    func tspanDxFollowsThePreviousSegment() throws {
        let raw = try rawSvgOp(##"<text x="10" y="40" font-size="20" fill="#000000" font-family="Helvetica"><tspan>I</tspan><tspan dx="30">I</tspan></text>"##)
        let (pixels, _) = try renderOps([raw])
        #expect(pixels.inkCount(x: 8..<18, y: 20..<45) > 0, "첫 I")
        #expect(pixels.inkCount(x: 18..<38, y: 20..<45) == 0, "dx=30만큼 띄운 사이는 비어 있다")
        #expect(pixels.inkCount(x: 40..<60, y: 20..<45) > 0, "둘째 I")
    }

    @Test("path 문법: 상대 명령, 암묵적 lineto, H·V·Z")
    func pathGrammar() throws {
        let raw = try rawSvgOp(##"<path d="m10,10 h30 v30 h-30 z" fill="#ff0000"/>"##)
        let (pixels, _) = try renderOps([raw])
        #expect(isNear(pixels.rgb(25, 25), red))
        #expect(isWhite(pixels.rgb(45, 25)))
        #expect(isWhite(pixels.rgb(25, 45)))
    }

    @Test("무늬 칠은 단색으로 잘못 칠하지 않고 건너뛰며 집계한다")
    func urlPaintIsSkipped() throws {
        let raw = try rawSvgOp(##"<rect x="10" y="10" width="30" height="30" fill="url(#hatch)"/>"##)
        let (pixels, report) = try renderOps([raw])
        #expect(isWhite(pixels.rgb(25, 25)))
        #expect(report.skipped["svg:paint(url)"] == 1)
    }

    @Test("각주 표식은 bbox 안쪽 위에 작은 글자로 그려진다")
    func footnoteMarker() throws {
        let marker = ##"{"type":"footnoteMarker","bbox":{"x":10,"y":10,"width":8,"height":10},"text":"1","fontFamily":"Helvetica","fontSize":8,"color":"#000000"}"##
        let (pixels, report) = try renderOps([marker])
        // 기준선은 bbox 위에서 40% 아래(y=14). 8px 글자라 위로 6px 정도, 아래로는 거의 없다.
        #expect(pixels.inkCount(x: 8..<20, y: 7..<16) > 0)
        #expect(pixels.inkCount(x: 8..<20, y: 17..<30) == 0, "기준선 아래는 비어 있다")
        #expect(report.rendered["op:footnoteMarker"] == 1)
    }

    @Test("OLE 자리 표시는 칠과 테두리를 그리고, 그림 미지정은 인쇄 출력처럼 그리지 않는다")
    func placeholders() throws {
        let ole = ##"{"type":"placeholder","bbox":{"x":10,"y":10,"width":80,"height":40},"kind":"ole","fillColor":"#eeeeff","strokeColor":"#333333","label":""}"##
        let (oleOut, oleReport) = try renderOps([ole])
        #expect(isNear(oleOut.rgb(20, 40), (0xee, 0xee, 0xff), tolerance: 2), "상자 안쪽 칠")
        #expect(isWhite(oleOut.rgb(5, 40)))
        #expect(oleReport.rendered["op:placeholder"] == 1)

        let missing = ole.replacingOccurrences(of: #""kind":"ole""#, with: #""kind":"missingPicture""#)
        let (missingOut, missingReport) = try renderOps([missing])
        #expect(isWhite(missingOut.rgb(20, 40)), "그림 미지정은 인쇄 출력에 나오지 않는다")
        #expect(missingReport.rendered["op:placeholder(missingPicture,hidden)"] == 1)
    }

    @Test("양식 개체는 사각형·원·열린 폴리라인을 그린다")
    func formObject() throws {
        let form = ##"""
        {"type":"formObject","bbox":{"x":0,"y":0,"width":100,"height":100},"formType":"pushButton","caption":"","text":"",
         "foreColor":"#000000","backColor":"#c0c0c0","value":0,"enabled":true,
         "drawing":{"primitives":[
           {"kind":"rect","bbox":{"x":10,"y":10,"width":30,"height":20},"color":"#ff0000"},
           {"kind":"circle","x":70,"y":20,"radius":8,"color":"#0000ff"},
           {"kind":"polyline","points":[[10,80],[60,80]],"color":"#00ff00","width":4,"closed":false}],
          "label":null}}
        """##
        let (pixels, report) = try renderOps([form])
        #expect(isNear(pixels.rgb(20, 20), red))
        #expect(isNear(pixels.rgb(70, 20), blue))
        #expect(isNear(pixels.rgb(30, 80), green))
        #expect(isWhite(pixels.rgb(30, 70)))
        #expect(report.rendered["op:formObject"] == 1)
    }
}

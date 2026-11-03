import CoreGraphics
import CoreText
import Foundation
import RhwpKit
@testable import RhwpRender
import Testing

private let red = (r: 255, g: 0, b: 0)
private let blue = (r: 0, g: 0, b: 255)

/// 글자 장식 op. 밑줄·취소선·강조점은 같은 모양에 `kind`와 선 모양만 다르다.
private func decoration(
    kind: String, shape: Int = 0, underline: String = "none", emphasisDot: Int = 0, fontSize: Double = 20,
    positions: [Double] = [0, 30, 60]
) -> String {
    let pos = positions.map { String($0) }.joined(separator: ",")
    return """
    {"type":"textDecoration","bbox":{"x":10,"y":20,"width":60,"height":30},"decoration":{"kind":"\(kind)","baseline":30,
     "rotation":0,"isVertical":false,"fontSize":\(fontSize),"ratio":1,"color":"#ff0000","shape":\(shape),
     "underline":"\(underline)","emphasisDot":\(emphasisDot),"positions":[\(pos)]}}
    """
}

@Suite("글자 장식과 탭 리더")
struct DecorationTests {
    // 기준선은 bbox 위(20) + baseline(30) = 50.

    @Test("밑줄은 기준선 아래 0.17em에 run 폭만큼 그려진다")
    func underlinePosition() throws {
        let (pixels, report) = try renderOps([decoration(kind: "underline", underline: "bottom")])
        // 20px 글자: 50 + 20 × 0.17 = 53.4. 굵기 1이라 y 52.9…53.9 → 행 53이 거의 덮인다.
        #expect(pixels.rgb(40, 53).g < 80 && pixels.rgb(40, 53).r > 200, "밑줄 행")
        #expect(isWhite(pixels.rgb(40, 58)), "밑줄 아래는 비어 있다")
        #expect(isWhite(pixels.rgb(40, 48)), "기준선 위는 비어 있다")
        #expect(isWhite(pixels.rgb(5, 53)) && isWhite(pixels.rgb(75, 53)), "run 폭(x 10…70) 밖")
        #expect(report.rendered["op:textDecoration"] == 1)
    }

    @Test("취소선은 기준선 위 0.3em에 그려진다")
    func strikethroughPosition() throws {
        let (pixels, _) = try renderOps([decoration(kind: "strikethrough")])
        // 50 − 20 × 0.3 = 44. 굵기 1이라 행 43·44에 반씩 걸친다.
        #expect(pixels.rgb(40, 44).g < 200, "취소선 행")
        #expect(isWhite(pixels.rgb(40, 50)), "밑줄 자리에는 없다")
    }

    @Test("이중 밑줄은 글자 크기에 비례해 두 줄로 갈라진다(한글 2022 실측표)")
    func doubleUnderlineScalesWithFontSize() throws {
        // 40px 글자: 기준선 50 + 40 × 0.160 = 56.4, 50 + 40 × 0.250 = 60. 굵기는 40 × 0.032 = 1.28.
        let (pixels, _) = try renderOps([decoration(kind: "underline", shape: 7, underline: "bottom", fontSize: 40)])
        #expect(!isWhite(pixels.rgb(40, 56)), "윗줄")
        #expect(isWhite(pixels.rgb(40, 58)), "두 줄 사이")
        #expect(!isWhite(pixels.rgb(40, 60)), "아랫줄")
    }

    @Test("강조점은 글자마다 글자 폭의 가운데, 기준선 위 1.05em에 찍힌다")
    func emphasisDotsPerCharacter() throws {
        let (pixels, _) = try renderOps([decoration(kind: "emphasisDot", emphasisDot: 1)])
        // x = 10 + position + 20 × 0.5: 20과 50(위치 60은 run의 끝이라 점이 없다). y = 50 − 21 = 29.
        #expect(pixels.inkCount(x: 16..<25, y: 22..<32) > 0, "첫 글자 위")
        #expect(pixels.inkCount(x: 46..<55, y: 22..<32) > 0, "둘째 글자 위")
        #expect(pixels.inkCount(x: 30..<42, y: 20..<34) == 0, "글자 사이에는 없다")
        #expect(pixels.inkCount(x: 66..<80, y: 20..<34) == 0, "run 끝에는 점이 없다")
    }

    @Test("글자 run은 스타일에 밑줄이 있어도 직접 그리지 않는다(장식 op가 그린다)")
    func textRunDoesNotDrawItsOwnUnderline() throws {
        let run = ##"""
        {"type":"textRun","bbox":{"x":10,"y":40,"width":10,"height":20},"text":"I","baseline":20,
         "placement":{"runToPage":{"a":1,"b":0,"c":0,"d":1,"e":10,"f":60}},"positions":[0,10],
         "style":{"fontFamily":"Helvetica","fontSize":20,"color":"#000000","underline":"bottom","strikethrough":true}}
        """##
        let (pixels, _) = try renderOps([run])
        // 밑줄 행(60 + 3.4)과 취소선 행(60 − 6)에는 "I" 글리프 줄기만 있고 가로선은 없다: 줄기 폭 밖은 흰색.
        #expect(isWhite(pixels.rgb(19, 63)), "밑줄이 직접 그려지면 x 10…20 전체가 칠해진다")
        #expect(isWhite(pixels.rgb(19, 54)), "취소선도 마찬가지")
    }

    @Test("탭 리더 실선은 글자 세로 중앙에 start…end 구간만 그려진다")
    func solidLeader() throws {
        let leader = ##"""
        {"type":"tabLeader","bbox":{"x":10,"y":20,"width":100,"height":30},
         "leaders":[{"startX":20,"endX":80,"fillType":1}],"color":"#000000","fontSize":20,"baseline":30,"rotation":0,"isVertical":false}
        """##
        let (pixels, report) = try renderOps([leader])
        // y = 20 + 30 − 20 × 0.35 = 43. 굵기 0.5라 행 42·43에 4분의 1씩 걸친다. x는 10 + 20 = 30 … 90.
        #expect(pixels.rgb(60, 43).g < 230, "리더 행")
        #expect(isWhite(pixels.rgb(20, 43)), "시작 전")
        #expect(isWhite(pixels.rgb(95, 43)), "끝 뒤")
        #expect(report.rendered["op:tabLeader"] == 1)
    }

    @Test("탭 리더 점선은 끊긴 둥근 점이다")
    func dottedLeaderHasGaps() throws {
        let leader = ##"""
        {"type":"tabLeader","bbox":{"x":10,"y":20,"width":100,"height":30},
         "leaders":[{"startX":20,"endX":80,"fillType":3}],"color":"#000000","fontSize":20,"baseline":30,"rotation":0,"isVertical":false}
        """##
        let (pixels, _) = try renderOps([leader])
        var inked = 0
        for x in 30..<90 where (40..<46).contains(where: { !isWhite(pixels.rgb(x, $0)) }) { inked += 1 }
        // 점 지름 0.12em = 2.4px, 간격 0.248em = 4.96px → 60px에 12개 안팎. 실선이면 60열이 모두 찬다.
        #expect((8...50).contains(inked), "잉크가 있는 열 \(inked)/60")
    }

    @Test("장식선 폭: 줄 끝 공백을 걷어내지 않았으면 배치 폭, 걷어냈으면 글자 위치의 끝")
    func decorationWidthRule() {
        #expect(Drawing.decorationWidth(positions: [0, 10, 20], layoutWidth: 20.3) == 20.3, "작성기 측정과 0.3px 어긋남 → 배치 폭")
        #expect(Drawing.decorationWidth(positions: [0, 10], layoutWidth: 25) == 10, "공백을 걷어냄 → 글자 끝")
        #expect(Drawing.decorationWidth(positions: [], layoutWidth: 0) == 0)
    }
}

@Suite("그라데이션")
struct GradientTests {
    private func gradientRect(width: Int, height: Int, type: Int) -> String {
        """
        {"type":"rectangle","bbox":{"x":0,"y":0,"width":\(width),"height":\(height)},
         "style":{"fillColor":"#00ff00","strokeColor":null,"strokeWidth":0,"strokeDash":"solid","opacity":1},
         "gradient":{"gradientType":\(type),"angle":0,"centerX":50,"centerY":50,"colors":["#ff0000","#0000ff"],"positions":[0,1]}}
        """
    }

    @Test("원형 그라데이션은 중심이 첫 색, 반지름의 절반에서 중간색, 바깥은 끝 색이다")
    func radialStops() throws {
        let (pixels, report) = try renderOps([gradientRect(width: 100, height: 100, type: 2)])
        #expect(isNear(pixels.rgb(50, 50), red, tolerance: 8), "중심")
        #expect(isNear(pixels.rgb(75, 50), (127, 0, 127), tolerance: 8), "반지름 0.5의 절반")
        #expect(isNear(pixels.rgb(2, 2), blue, tolerance: 2), "모서리는 끝 색으로 채운다(SVG pad)")
        #expect(report.skipped.isEmpty, "\(report.skipped)")
    }

    @Test("원형은 상자 비율을 따르는 타원이다(가로가 긴 상자에서도 가로·세로 끝이 같은 단계)")
    func radialIsEllipticalInBoxUnits() throws {
        let (pixels, _) = try renderOps([gradientRect(width: 100, height: 50, type: 2)])
        // 중심 (50, 25). 가로로 25px(= 폭의 0.25), 세로로 12.5px(= 높이의 0.25)는 둘 다 반지름 0.5의 절반이다.
        let horizontal = pixels.rgb(75, 25)
        let vertical = pixels.rgb(50, 37)
        #expect(isNear(horizontal, (127, 0, 127), tolerance: 12), "가로 \(horizontal)")
        #expect(isNear(vertical, (127, 0, 127), tolerance: 16), "세로 \(vertical)")
    }
}

/// 가로 4px·세로 4px, 왼쪽 절반 빨강·오른쪽 절반 파랑인 PNG. 렌더러 자신으로 만든다.
private func twoToneImage() throws -> String {
    let tree = try makeLeafTree(ops: [
        OpJSON.rectangle(x: 0, y: 0, w: 2, h: 4, fill: "#ff0000"),
        OpJSON.rectangle(x: 2, y: 0, w: 2, h: 4, fill: "#0000ff"),
    ], width: 4, height: 4)
    let data = try #require(PageRenderer().render(tree, scale: 1).pngData())
    return data.base64EncodedString()
}

private func imageOp(
    _ base64: String, bbox: (Int, Int, Int, Int) = (10, 10, 40, 40), fillMode: String = "fitToSize", extra: String = ""
) -> String {
    """
    {"type":"image","bbox":{"x":\(bbox.0),"y":\(bbox.1),"width":\(bbox.2),"height":\(bbox.3)},"mime":"image/png",
     "base64":"\(base64)","fillMode":"\(fillMode)"\(extra)}
    """
}

@Suite("그림")
struct ImageTests {
    @Test("늘이기(fitToSize)는 그림 전체를 상자에 채운다")
    func fitToSize() throws {
        let (pixels, report) = try renderOps([imageOp(try twoToneImage())])
        #expect(isNear(pixels.rgb(15, 30), red), "왼쪽 절반")
        #expect(isNear(pixels.rgb(45, 30), blue), "오른쪽 절반")
        #expect(isWhite(pixels.rgb(5, 30)) && isWhite(pixels.rgb(55, 30)))
        #expect(report.rendered["op:image"] == 1)
    }

    @Test("잘라내기는 원본의 그 부분만 상자에 채운다(기준 크기 300HU = 4px → 75HU/px)")
    func crop() throws {
        // 오른쪽 절반(x 150…300 HU = 2…4px)만 보이므로 상자 전체가 파랑이다.
        let extra = #","crop":{"left":150,"top":0,"right":300,"bottom":300},"originalSizeHu":[300,300]"#
        let (pixels, _) = try renderOps([imageOp(try twoToneImage(), extra: extra)])
        #expect(isNear(pixels.rgb(15, 30), blue), "원래 빨강이던 왼쪽도 파랑이다")
        #expect(isNear(pixels.rgb(45, 30), blue))
    }

    @Test("세로가 뒤집힌 잘라내기는 무시하고 그림 전체를 그린다(한컴 PDF 관측)")
    func invertedCropHeightDrawsTheWholePicture() throws {
        let extra = #","crop":{"left":0,"top":6240,"right":304,"bottom":2619}"#
        let (pixels, report) = try renderOps([imageOp(try twoToneImage(), extra: extra)])
        #expect(isNear(pixels.rgb(15, 30), red) && isNear(pixels.rgb(45, 30), blue), "그림 전체가 상자에 채워진다")
        #expect(report.rendered["op:image"] == 1)
    }

    @Test("가로가 빈 잘라내기는 그림을 그리지 않는다")
    func emptyCrop() throws {
        let extra = #","crop":{"left":100,"top":0,"right":100,"bottom":300}"#
        let (pixels, report) = try renderOps([imageOp(try twoToneImage(), extra: extra)])
        #expect(isWhite(pixels.rgb(30, 30)))
        #expect(report.rendered["op:image(emptyCrop)"] == 1)
    }

    @Test("zoom은 종횡비를 지켜 상자 가운데에 맞춘다")
    func zoom() throws {
        // 상자 40×20에 정사각 그림: 20×20이 가운데(x 20…40)에 놓이고 양옆은 비어 있다.
        let (pixels, _) = try renderOps([imageOp(try twoToneImage(), bbox: (10, 10, 40, 20), fillMode: "zoom")])
        #expect(isWhite(pixels.rgb(14, 20)), "왼쪽 여백")
        #expect(isNear(pixels.rgb(25, 20), red))
        #expect(isNear(pixels.rgb(35, 20), blue))
        #expect(isWhite(pixels.rgb(46, 20)), "오른쪽 여백")
    }

    @Test("배치 모드는 원래 크기로 정렬해 놓는다")
    func positioned() throws {
        let extra = #","originalSize":{"width":8,"height":8}"#
        let (pixels, _) = try renderOps([imageOp(try twoToneImage(), fillMode: "leftTop", extra: extra)])
        #expect(isNear(pixels.rgb(12, 12), red))
        #expect(isNear(pixels.rgb(16, 12), blue))
        #expect(isWhite(pixels.rgb(20, 12)), "8px 밖")
    }

    @Test("바둑판은 원래 크기로 되풀이된다")
    func tiled() throws {
        let extra = #","originalSize":{"width":8,"height":8}"#
        let (pixels, _) = try renderOps([imageOp(try twoToneImage(), fillMode: "tileAll", extra: extra)])
        #expect(isNear(pixels.rgb(12, 12), red), "첫 타일 왼쪽")
        #expect(isNear(pixels.rgb(16, 12), blue), "첫 타일 오른쪽")
        #expect(isNear(pixels.rgb(20, 12), red), "둘째 타일 왼쪽(x 18부터)")
        #expect(isNear(pixels.rgb(24, 12), blue))
    }

    @Test("투명도와 뒤집기는 그림에도 적용된다")
    func opacityAndFlip() throws {
        let half = try renderOps([imageOp(try twoToneImage(), extra: #","opacity":0.5"#)]).pixels
        #expect(isNear(half.rgb(15, 30), (255, 128, 128), tolerance: 6), "빨강 위에 흰 쪽이 절반 비친다")

        let flipped = try renderOps([imageOp(
            try twoToneImage(), extra: #","transform":{"rotation":0,"horzFlip":true,"vertFlip":false}"#
        )]).pixels
        #expect(isNear(flipped.rgb(15, 30), blue), "좌우를 뒤집으면 왼쪽이 파랑")
        #expect(isNear(flipped.rgb(45, 30), red))
    }

    @Test("90° 회전한 그림은 회전 전 틀(가로·세로 맞바꿈)에 그린 뒤 돌려 bbox를 정확히 덮는다(이중 회전 방지)")
    func rotatedPictureFillsItsBoundingBox() throws {
        // bbox (10,10) 20×40, 중심 (20,30). 회전 전 틀은 40×20이다. 시계 방향 90°로 돌리면 그림의 왼쪽(빨강)이 위로,
        // 오른쪽(파랑)이 아래로 간다.
        let extra = #","transform":{"rotation":90,"horzFlip":false,"vertFlip":false}"#
        let (pixels, _) = try renderOps([imageOp(try twoToneImage(), bbox: (10, 10, 20, 40), extra: extra)])
        #expect(isNear(pixels.rgb(20, 15), red), "위쪽 절반")
        #expect(isNear(pixels.rgb(20, 45), blue), "아래쪽 절반")
        #expect(isWhite(pixels.rgb(35, 30)), "bbox 오른쪽 밖 — 틀을 맞바꾸지 않으면 가로로 튀어나온다")
        #expect(isWhite(pixels.rgb(5, 30)), "bbox 왼쪽 밖")
    }

    @Test("SVG 그림: 늘이기는 상자에 맞추고 zoom은 비율을 지킨다")
    func svgImage() throws {
        let svg = ##"<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><rect width="5" height="10" fill="#ff0000"/><rect x="5" width="5" height="10" fill="#0000ff"/></svg>"##
        let base64 = Data(svg.utf8).base64EncodedString()
        func op(_ mode: String, _ box: (Int, Int, Int, Int)) -> String {
            imageOp(base64, bbox: box, fillMode: mode).replacingOccurrences(of: "image/png", with: "image/svg+xml")
        }
        let stretched = try renderOps([op("fitToSize", (10, 10, 60, 20))])
        #expect(isNear(stretched.pixels.rgb(20, 20), red) && isNear(stretched.pixels.rgb(60, 20), blue), "가로로 늘어남")
        #expect(stretched.report.skipped.isEmpty, "\(stretched.report.skipped)")

        let zoomed = try renderOps([op("zoom", (10, 10, 60, 20))])
        #expect(isWhite(zoomed.pixels.rgb(15, 20)), "정사각 viewBox는 20×20으로 가운데에 놓인다")
        #expect(isNear(zoomed.pixels.rgb(34, 20), red) && isNear(zoomed.pixels.rgb(46, 20), blue))
    }

    @Test("잘라내기 좌표 변환: 기준 크기가 있으면 그것으로, 없으면 축별 추정, 그것도 안 되면 75HU/px")
    func cropSourceRules() throws {
        // ① 기준 크기 7500×3750HU, 그림 100×50px → 75HU/px. crop (750, 0, 3750, 3750) → x 10, 폭 40, 높이 50.
        let known = Drawing.cropSource(
            try makeCrop(750, 0, 3750, 3750), referenceHU: [7500, 3750], imageSize: CGSize(width: 100, height: 50)
        )
        #expect(known == CGRect(x: 10, y: 0, width: 40, height: 50))

        // ② 기준 없음, 가로는 left == 0이라 right가 전체 범위(88560/1181 ≈ 74.99HU/px), 세로는 top > 0이라 추정 불가
        //    → 가로 배율을 두 축에 쓴다(실제 문서 30442의 사례).
        let adaptive = Drawing.cropSource(
            try makeCrop(0, 20745, 88560, 45453), referenceHU: nil, imageSize: CGSize(width: 1181, height: 945)
        )
        #expect(abs(adaptive.minY - 276.65) < 0.01 && abs(adaptive.height - 329.50) < 0.01 && abs(adaptive.width - 1181) < 0.01)

        // ①′ 기준 크기의 가로·세로 배율이 다르면(75와 150HU/px) 축마다 자기 배율로 나눈다.
        let anisotropic = Drawing.cropSource(
            try makeCrop(750, 1500, 3750, 7500), referenceHU: [7500, 7500], imageSize: CGSize(width: 100, height: 50)
        )
        #expect(anisotropic == CGRect(x: 10, y: 10, width: 40, height: 40))

        // ③ 어느 축도 추정할 수 없으면 표준 75HU/px.
        let standard = Drawing.cropSource(
            try makeCrop(750, 1500, 3750, 3000), referenceHU: nil, imageSize: CGSize(width: 100, height: 50)
        )
        #expect(standard == CGRect(x: 10, y: 20, width: 40, height: 20))
    }
}

/// `ImageCrop`은 엔진 JSON에서만 만들어지므로 시험도 JSON으로 만든다.
private func makeCrop(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) throws -> ImageOp.ImageCrop {
    try JSONDecoder().decode(
        ImageOp.ImageCrop.self, from: Data(#"{"left":\#(left),"top":\#(top),"right":\#(right),"bottom":\#(bottom)}"#.utf8)
    )
}

@Suite("글꼴 해석")
struct FontResolutionTests {
    private func family(_ font: FontResolver.ResolvedFont) -> String { CTFontCopyFamilyName(font.font) as String }

    @Test("쉼표 목록은 설치된 첫 글꼴을 쓰고 요청한 글꼴과 다르면 대체로 보고한다")
    func familyList() {
        let resolved = FontResolver().resolve(familyList: "'RHWP-NoSuchFont', Helvetica, serif", size: 12, bold: false, italic: false)
        #expect(family(resolved) == "Helvetica")
        #expect(resolved.requested == "RHWP-NoSuchFont")
        #expect(resolved.substitute == "Helvetica")
    }

    @Test("설치된 글꼴은 대체 없이 그대로 쓴다")
    func installedFontIsNotSubstituted() {
        let resolved = FontResolver().resolve(family: "Helvetica", size: 12, bold: false, italic: false)
        #expect(family(resolved) == "Helvetica" && resolved.substitute == nil)
    }

    @Test("라틴 글꼴은 같은 모양의 글꼴로, 명조 계열은 명조로, 나머지는 고딕으로 대체한다")
    func substitutionClasses() {
        let resolver = FontResolver()
        #expect(family(resolver.resolve(family: "Palatino Linotype", size: 12, bold: false, italic: false)) == "Palatino")
        let serif = family(resolver.resolve(family: "RHWP 신명조 시험", size: 12, bold: false, italic: false))
        #expect(["Nanum Myeongjo", "AppleMyungjo"].contains(serif), "명조 계열 → \(serif)")
        #expect(family(resolver.resolve(family: "RHWP-NoSuchFont", size: 12, bold: false, italic: false)) == "Apple SD Gothic Neo")
        let headline = family(resolver.resolve(family: "HY헤드라인M", size: 12, bold: false, italic: false))
        #expect(["HeadLineA", "Apple SD Gothic Neo"].contains(headline), "헤드라인 → \(headline)")
    }

    @Test("수식 글꼴 목록은 설치된 수식용 글꼴로 해석된다")
    func equationFontList() {
        let resolved = FontResolver().resolve(
            familyList: "'Latin Modern Math', 'STIX Two Text', 'STIX Two Math', 'Times New Roman', 'Times', serif",
            size: 12, bold: false, italic: true
        )
        #expect(["Latin Modern Math", "STIX Two Text"].contains(family(resolved)), Comment(rawValue: family(resolved)))
    }
}

@Suite("SVG 문법 보조")
struct SVGSyntaxTests {
    @Test("수 목록: 붙어 있는 부호·소수점·지수를 규격대로 쪼갠다")
    func numbers() {
        #expect(SVGFragmentDrawer.numbers(in: "1.5.5-2 3e1,4") == [1.5, 0.5, -2, 30, 4])
        #expect(SVGFragmentDrawer.numbers(in: "") == [])
        #expect(SVGFragmentDrawer.numbers(in: "12px") == [12], "단위 앞까지만 읽는다")
    }

    @Test("변환 목록은 점에 오른쪽 것부터 적용한다")
    func transformOrder() throws {
        // translate(10 20) scale(2): 점 (1,1)은 먼저 2배(→ 2,2) 된 뒤 이동(→ 12,22).
        let t = try #require(SVGFragmentDrawer.parseTransform("translate(10 20) scale(2)"))
        let p = CGPoint(x: 1, y: 1).applying(t)
        #expect(abs(p.x - 12) < 1e-9 && abs(p.y - 22) < 1e-9)
        // rotate(90 10 10): SVG의 양의 각도는 화면에서 시계 방향. (20,10) → (10,20).
        let r = try #require(SVGFragmentDrawer.parseTransform("rotate(90 10 10)"))
        let q = CGPoint(x: 20, y: 10).applying(r)
        #expect(abs(q.x - 10) < 1e-9 && abs(q.y - 20) < 1e-9)
        #expect(SVGFragmentDrawer.parseTransform("skewX(10)") == nil, "모르는 함수는 적용하지 않는다")
    }
}

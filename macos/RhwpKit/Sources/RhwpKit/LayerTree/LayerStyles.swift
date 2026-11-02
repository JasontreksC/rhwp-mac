import Foundation

// 레이어 트리의 스타일 값 타입.
//
// 열거형 값은 엔진이 새 값을 더해도 쪽 전체를 못 그리는 일이 없도록, 모르는 문자열을 안전한 기본값으로
// 낮춘다(아래 각 타입에 기본값을 적었다). 그래서 새 값이 생기면 렌더러가 조용히 기본 모양으로 그릴 수 있으니,
// 엔진 스키마를 올릴 때는 이 파일을 함께 갱신해야 한다.

/// 선 모양. 알 수 없는 값은 `.solid`.
public enum StrokeDash: String, Sendable, Equatable, Decodable {
    case solid, dash, dot, dashDot, dashDotDot

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StrokeDash(rawValue: raw) ?? .solid
    }
}

/// 밑줄 위치. 알 수 없는 값은 `.none`.
public enum UnderlineKind: String, Sendable, Equatable, Decodable {
    case none, bottom, top

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UnderlineKind(rawValue: raw) ?? .none
    }
}

/// 글자 스타일. 글꼴 이름은 문서가 지정한 이름 그대로이며(예: `HY헤드라인M`) 맥에 설치된 글꼴이라는 보장은 없다.
public struct TextStyle: Sendable, Equatable, Decodable {
    public var fontFamily: String
    /// px 단위 글자 크기.
    public var fontSize: Double
    public var color: LayerColor
    public var bold: Bool
    public var italic: Bool
    /// 장평(가로 배율). 1이면 100%.
    public var ratio: Double
    public var underline: UnderlineKind
    public var underlineColor: LayerColor?
    public var strikethrough: Bool
    public var strikeColor: LayerColor?
    public var superscript: Bool
    public var `subscript`: Bool

    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, color, bold, italic, ratio
        case underline, underlineColor, strikethrough, strikeColor, superscript, `subscript`
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try c.decode(String.self, forKey: .fontFamily)
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        color = try c.decode(LayerColor.self, forKey: .color)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        ratio = try c.decodeIfPresent(Double.self, forKey: .ratio) ?? 1
        underline = try c.decodeIfPresent(UnderlineKind.self, forKey: .underline) ?? .none
        underlineColor = try c.decodeIfPresent(LayerColor.self, forKey: .underlineColor)
        strikethrough = try c.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
        strikeColor = try c.decodeIfPresent(LayerColor.self, forKey: .strikeColor)
        superscript = try c.decodeIfPresent(Bool.self, forKey: .superscript) ?? false
        `subscript` = try c.decodeIfPresent(Bool.self, forKey: .subscript) ?? false
    }
}

/// 선 스타일(선 개체, 경로의 선).
public struct LineStyle: Sendable, Equatable, Decodable {
    public var color: LayerColor
    public var width: Double
    public var dash: StrokeDash

    private enum CodingKeys: String, CodingKey { case color, width, dash }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decode(LayerColor.self, forKey: .color)
        width = try c.decode(Double.self, forKey: .width)
        dash = try c.decodeIfPresent(StrokeDash.self, forKey: .dash) ?? .solid
    }
}

/// 도형 채우기·테두리 스타일. `fillColor`/`strokeColor`가 nil이면 칠하지 않는다.
public struct ShapeStyle: Sendable, Equatable, Decodable {
    public var fillColor: LayerColor?
    public var strokeColor: LayerColor?
    public var strokeWidth: Double
    public var strokeDash: StrokeDash
    public var opacity: Double

    private enum CodingKeys: String, CodingKey { case fillColor, strokeColor, strokeWidth, strokeDash, opacity }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fillColor = try c.decodeIfPresent(LayerColor.self, forKey: .fillColor)
        strokeColor = try c.decodeIfPresent(LayerColor.self, forKey: .strokeColor)
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 0
        strokeDash = try c.decodeIfPresent(StrokeDash.self, forKey: .strokeDash) ?? .solid
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
    }
}

/// 그라데이션 채우기. `colors`와 `positions`는 같은 길이이고 `positions`는 0...1이다.
///
/// `gradientType`은 한컴 값(1 줄무늬, 2 원형, 3 원뿔, 4 사각)이다. 원형(2)을 뺀 나머지는 엔진의 SVG 렌더러처럼
/// 선형으로 근사해 그린다. 원형은 렌더러가 따로 처리해야 한다.
public struct Gradient: Sendable, Equatable, Decodable {
    public var gradientType: Int
    public var angle: Int
    public var centerX: Int
    public var centerY: Int
    public var colors: [LayerColor]
    public var positions: [Double]

    /// 선형 그라데이션의 시작·끝점. 엔진 정본(`src/renderer/mod.rs`의 `linear_gradient_axis`)과 같은 규칙이다:
    /// 방향 = (sin θ, −cos θ), 중심에서 정사영 길이의 절반만큼 양쪽으로 벌린다.
    /// 그래서 θ=0은 아래→위, θ=90은 좌→우다. 이 규칙은 레이어 트리에 풀려 있지 않고 각도만 실려 오므로
    /// 소비자가 직접 구현해야 하며, 0단계에서 방향을 잘못 가정했다가 한컴 PDF와 대조해 바로잡았다.
    public func linearAxis(in bounds: LayerRect) -> (start: LayerPoint, end: LayerPoint) {
        let radians = Double(angle) * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        let cx = bounds.x + bounds.width / 2
        let cy = bounds.y + bounds.height / 2
        let half = (abs(dx) * bounds.width + abs(dy) * bounds.height) / 2
        return (
            LayerPoint(x: cx - dx * half, y: cy - dy * half),
            LayerPoint(x: cx + dx * half, y: cy + dy * half)
        )
    }
}

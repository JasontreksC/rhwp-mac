import Foundation

/// 레이어 트리 잎(leaf)에 담기는 그리기 명령. 그리는 순서는 배열 순서다.
///
/// 렌더러가 아직 다루지 않는 종류(`textDecoration`, `tabLeader` 등)는 `.unsupported`로 보존해
/// 디코딩이 실패하지 않게 하고, 렌더러가 건너뛴 종류를 집계할 수 있게 한다.
public enum PaintOp: Sendable, Equatable, Decodable {
    case pageBackground(PageBackgroundOp)
    case textRun(TextRunOp)
    case line(LineOp)
    case rectangle(RectangleOp)
    case ellipse(EllipseOp)
    case path(PathOp)
    case image(ImageOp)
    /// 이 버전이 모델링하지 않은 op. `type`은 엔진이 붙인 이름(예: `"tabLeader"`)이다.
    case unsupported(type: String)

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: any Decoder) throws {
        let type = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch type {
        case "pageBackground": self = .pageBackground(try PageBackgroundOp(from: decoder))
        case "textRun": self = .textRun(try TextRunOp(from: decoder))
        case "line": self = .line(try LineOp(from: decoder))
        case "rectangle": self = .rectangle(try RectangleOp(from: decoder))
        case "ellipse": self = .ellipse(try EllipseOp(from: decoder))
        case "path": self = .path(try PathOp(from: decoder))
        case "image": self = .image(try ImageOp(from: decoder))
        default: self = .unsupported(type: type)
        }
    }

    /// 엔진이 붙인 op 이름. 집계·로그용이다.
    public var typeName: String {
        switch self {
        case .pageBackground: "pageBackground"
        case .textRun: "textRun"
        case .line: "line"
        case .rectangle: "rectangle"
        case .ellipse: "ellipse"
        case .path: "path"
        case .image: "image"
        case let .unsupported(type): type
        }
    }
}

public struct PageBackgroundOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var backgroundColor: LayerColor?
    public var borderColor: LayerColor?
    public var borderWidth: Double

    private enum CodingKeys: String, CodingKey { case bbox, backgroundColor, borderColor, borderWidth }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        backgroundColor = try c.decodeIfPresent(LayerColor.self, forKey: .backgroundColor)
        borderColor = try c.decodeIfPresent(LayerColor.self, forKey: .borderColor)
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0
    }
}

/// 한 줄 안의 같은 스타일 글자 묶음.
///
/// 글자 배치는 엔진이 이미 끝냈다: `positions[i]`는 run 원점(`runToPage`의 이동 성분 `e`, `f`)에서 i번째
/// 유니코드 스칼라가 시작하는 x 오프셋이고, 마지막 값은 run의 끝이다(그래서 개수는 스칼라 수 + 1).
/// 렌더러는 줄 나눔·자간·장평 폭을 다시 계산하지 말고 이 위치에 글리프만 놓아야 한다.
public struct TextRunOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var text: String
    /// 엔진이 화면용으로 바꾼 글자(한컴 사용자 정의 영역 글자 등). 있으면 `text` 대신 이것을 그려야 한다.
    public var displayText: String?
    public var baseline: Double
    public var rotation: Double
    public var isVertical: Bool
    /// run 좌표를 쪽 좌표로 옮기는 변환. `e`, `f`가 기준선 위 run 원점이다.
    public var runToPage: LayerAffine
    public var positions: [Double]
    public var displayPositions: [Double]?
    public var style: TextStyle
    /// 문단 끝 표식(조판부호). 보통 화면에 그리지 않는다.
    public var isParaEnd: Bool
    public var isLineBreakEnd: Bool

    /// 실제로 그릴 글자.
    public var renderedText: String { displayText ?? text }
    /// `renderedText`에 대응하는 글자별 시작 x 오프셋.
    public var renderedPositions: [Double] { displayPositions ?? positions }

    private enum CodingKeys: String, CodingKey {
        case bbox, text, displayText, baseline, rotation, isVertical, placement
        case positions, displayPositions, style, isParaEnd, isLineBreakEnd
    }

    private struct Placement: Decodable {
        let runToPage: LayerAffine
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        text = try c.decode(String.self, forKey: .text)
        displayText = try c.decodeIfPresent(String.self, forKey: .displayText)
        baseline = try c.decode(Double.self, forKey: .baseline)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isVertical = try c.decodeIfPresent(Bool.self, forKey: .isVertical) ?? false
        runToPage = try c.decode(Placement.self, forKey: .placement).runToPage
        positions = try c.decode([Double].self, forKey: .positions)
        displayPositions = try c.decodeIfPresent([Double].self, forKey: .displayPositions)
        style = try c.decode(TextStyle.self, forKey: .style)
        isParaEnd = try c.decodeIfPresent(Bool.self, forKey: .isParaEnd) ?? false
        isLineBreakEnd = try c.decodeIfPresent(Bool.self, forKey: .isLineBreakEnd) ?? false
    }
}

public struct LineOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var start: LayerPoint
    public var end: LayerPoint
    public var style: LineStyle
    public var transform: ShapeTransform

    private enum CodingKeys: String, CodingKey { case bbox, x1, y1, x2, y2, style, transform }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        start = LayerPoint(x: try c.decode(Double.self, forKey: .x1), y: try c.decode(Double.self, forKey: .y1))
        end = LayerPoint(x: try c.decode(Double.self, forKey: .x2), y: try c.decode(Double.self, forKey: .y2))
        style = try c.decode(LineStyle.self, forKey: .style)
        transform = try c.decodeIfPresent(ShapeTransform.self, forKey: .transform) ?? .identity
    }
}

public struct RectangleOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var cornerRadius: Double
    public var style: ShapeStyle
    public var gradient: Gradient?
    public var transform: ShapeTransform

    private enum CodingKeys: String, CodingKey { case bbox, cornerRadius, style, gradient, transform }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
        style = try c.decode(ShapeStyle.self, forKey: .style)
        gradient = try c.decodeIfPresent(Gradient.self, forKey: .gradient)
        transform = try c.decodeIfPresent(ShapeTransform.self, forKey: .transform) ?? .identity
    }
}

public struct EllipseOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var style: ShapeStyle
    public var gradient: Gradient?
    public var transform: ShapeTransform

    private enum CodingKeys: String, CodingKey { case bbox, style, gradient, transform }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        style = try c.decode(ShapeStyle.self, forKey: .style)
        gradient = try c.decodeIfPresent(Gradient.self, forKey: .gradient)
        transform = try c.decodeIfPresent(ShapeTransform.self, forKey: .transform) ?? .identity
    }
}

/// 경로 그리기 명령. 좌표는 쪽 좌표다.
public enum PathCommand: Sendable, Equatable, Decodable {
    case moveTo(LayerPoint)
    case lineTo(LayerPoint)
    case curveTo(control1: LayerPoint, control2: LayerPoint, end: LayerPoint)
    /// SVG 타원호. 중심 매개변수로의 변환은 렌더러가 한다.
    case arcTo(rx: Double, ry: Double, rotation: Double, largeArc: Bool, sweep: Bool, end: LayerPoint)
    case closePath
    case unsupported(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, x, y, x1, y1, x2, y2, x3, y3, rx, ry, rotation, largeArc, sweep
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "moveTo":
            self = .moveTo(LayerPoint(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y)))
        case "lineTo":
            self = .lineTo(LayerPoint(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y)))
        case "curveTo":
            self = .curveTo(
                control1: LayerPoint(x: try c.decode(Double.self, forKey: .x1), y: try c.decode(Double.self, forKey: .y1)),
                control2: LayerPoint(x: try c.decode(Double.self, forKey: .x2), y: try c.decode(Double.self, forKey: .y2)),
                end: LayerPoint(x: try c.decode(Double.self, forKey: .x3), y: try c.decode(Double.self, forKey: .y3))
            )
        case "arcTo":
            self = .arcTo(
                rx: try c.decode(Double.self, forKey: .rx),
                ry: try c.decode(Double.self, forKey: .ry),
                rotation: try c.decode(Double.self, forKey: .rotation),
                largeArc: try c.decode(Bool.self, forKey: .largeArc),
                sweep: try c.decode(Bool.self, forKey: .sweep),
                end: LayerPoint(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y))
            )
        case "closePath":
            self = .closePath
        default:
            self = .unsupported(type: type)
        }
    }
}

public struct PathOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var commands: [PathCommand]
    public var style: ShapeStyle
    public var gradient: Gradient?
    /// 선 전용 경로의 선 스타일. 있으면 `style`의 테두리보다 이것을 쓴다.
    public var lineStyle: LineStyle?
    public var transform: ShapeTransform

    private enum CodingKeys: String, CodingKey { case bbox, commands, style, gradient, lineStyle, transform }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        commands = try c.decode([PathCommand].self, forKey: .commands)
        style = try c.decode(ShapeStyle.self, forKey: .style)
        gradient = try c.decodeIfPresent(Gradient.self, forKey: .gradient)
        lineStyle = try c.decodeIfPresent(LineStyle.self, forKey: .lineStyle)
        transform = try c.decodeIfPresent(ShapeTransform.self, forKey: .transform) ?? .identity
    }
}

/// 그림. 바이트는 응답 JSON의 base64에서 디코딩된다.
public struct ImageOp: Sendable, Equatable, Decodable {
    /// 그림이 그려질 자리(틀에서 그림 안쪽 여백을 뺀 사각형).
    public var bbox: LayerRect
    public var mime: String?
    /// 그림 바이트. 엔진이 생략하도록 요청된 경우(`imageBytesOmitted`)나 해석할 수 없는 그림이면 nil.
    public var imageData: Data?
    public var imageBytesOmitted: Bool
    /// 채우기 방식(`fillMode`). 한컴 값 이름 그대로다.
    public var fillMode: String?
    /// 원본 그림 크기(px).
    public var originalSize: ImageSize?
    /// 잘라내기. 원본 그림 좌표 단위(엔진이 준 값 그대로)다.
    public var crop: ImageCrop?
    public var opacity: Double
    public var transform: ShapeTransform

    public struct ImageSize: Sendable, Equatable, Decodable {
        public var width: Double
        public var height: Double
    }

    public struct ImageCrop: Sendable, Equatable, Decodable {
        public var left: Int
        public var top: Int
        public var right: Int
        public var bottom: Int
    }

    private enum CodingKeys: String, CodingKey {
        case bbox, mime, base64, imageBytesOmitted, fillMode, originalSize, crop, opacity, transform
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        mime = try c.decodeIfPresent(String.self, forKey: .mime)
        // JSONDecoder 의 기본 Data 전략이 base64 이므로 문자열이 곧바로 바이트로 디코딩된다.
        imageData = try c.decodeIfPresent(Data.self, forKey: .base64)
        imageBytesOmitted = try c.decodeIfPresent(Bool.self, forKey: .imageBytesOmitted) ?? false
        fillMode = try c.decodeIfPresent(String.self, forKey: .fillMode)
        originalSize = try c.decodeIfPresent(ImageSize.self, forKey: .originalSize)
        crop = try c.decodeIfPresent(ImageCrop.self, forKey: .crop)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        transform = try c.decodeIfPresent(ShapeTransform.self, forKey: .transform) ?? .identity
    }
}

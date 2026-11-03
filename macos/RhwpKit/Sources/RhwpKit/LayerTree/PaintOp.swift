import Foundation

/// 레이어 트리 잎(leaf)에 담기는 그리기 명령. 그리는 순서는 배열 순서다.
///
/// 렌더러가 아직 다루지 않는 종류(`charOverlap`, `glyphOutline` 등)는 `.unsupported`로 보존해
/// 디코딩이 실패하지 않게 하고, 렌더러가 건너뛴 종류를 집계할 수 있게 한다.
public enum PaintOp: Sendable, Equatable, Decodable {
    case pageBackground(PageBackgroundOp)
    case textRun(TextRunOp)
    case line(LineOp)
    case rectangle(RectangleOp)
    case ellipse(EllipseOp)
    case path(PathOp)
    case image(ImageOp)
    case equation(EquationOp)
    case textDecoration(TextDecorationOp)
    case tabLeader(TabLeaderOp)
    case footnoteMarker(FootnoteMarkerOp)
    case placeholder(PlaceholderOp)
    case formObject(FormObjectOp)
    case rawSvg(RawSvgOp)
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
        case "equation": self = .equation(try EquationOp(from: decoder))
        case "textDecoration": self = .textDecoration(try TextDecorationOp(from: decoder))
        case "tabLeader": self = .tabLeader(try TabLeaderOp(from: decoder))
        case "footnoteMarker": self = .footnoteMarker(try FootnoteMarkerOp(from: decoder))
        case "placeholder": self = .placeholder(try PlaceholderOp(from: decoder))
        case "formObject": self = .formObject(try FormObjectOp(from: decoder))
        case "rawSvg": self = .rawSvg(try RawSvgOp(from: decoder))
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
        case .equation: "equation"
        case .textDecoration: "textDecoration"
        case .tabLeader: "tabLeader"
        case .footnoteMarker: "footnoteMarker"
        case .placeholder: "placeholder"
        case .formObject: "formObject"
        case .rawSvg: "rawSvg"
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
    /// 잘라내기 좌표의 기준이 되는 원본 그림 크기(HWPUNIT). 엔진이 알면 준다.
    public var originalSizeHU: [Int]?
    /// 그림 효과(`realPic`, `grayScale`, `blackWhite`, `pattern8x8`)와 밝기·대비(-100...100).
    public var effect: String
    public var brightness: Int
    public var contrast: Int
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
        case bbox, mime, base64, imageBytesOmitted, fillMode, originalSize, crop, originalSizeHu, effect
        case brightness, contrast, opacity, transform
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
        originalSizeHU = try c.decodeIfPresent([Int].self, forKey: .originalSizeHu)
        effect = try c.decodeIfPresent(String.self, forKey: .effect) ?? "realPic"
        brightness = try c.decodeIfPresent(Int.self, forKey: .brightness) ?? 0
        contrast = try c.decodeIfPresent(Int.self, forKey: .contrast) ?? 0
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        transform = try c.decodeIfPresent(ShapeTransform.self, forKey: .transform) ?? .identity
    }
}

// MARK: - 수식·장식·탭 리더·각주 표식·양식·자리표시·원본 SVG

/// 수식. 엔진이 수식의 배치를 이미 끝내 **수식 원점 기준의 평평한 SVG 조각**(`text`·`line`·`path`·`circle`)으로
/// 보낸다. 렌더러는 이 조각을 bbox 왼쪽 위에 놓되, 저장된 수식 상자(bbox)와 엔진이 계산한 수식 크기
/// (`layoutWidth`·`layoutHeight`)가 다르면 엔진의 SVG 렌더러와 같은 규칙으로 늘이거나 줄인다.
/// 수식 트리(`layoutBox`)는 편집·히트 테스트용이라 크기만 읽고 나머지는 모델링하지 않는다.
public struct EquationOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var svgContent: String
    public var color: LayerColor
    public var fontSize: Double
    /// 엔진이 수식 스크립트로 계산한 고유 크기(px).
    public var layoutWidth: Double
    public var layoutHeight: Double

    private enum CodingKeys: String, CodingKey { case bbox, svgContent, color, fontSize, layoutBox }
    private enum LayoutKeys: String, CodingKey { case width, height }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        svgContent = try c.decode(String.self, forKey: .svgContent)
        color = try c.decodeIfPresent(LayerColor.self, forKey: .color) ?? LayerColor(red: 0, green: 0, blue: 0)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 10
        let layout = try c.nestedContainer(keyedBy: LayoutKeys.self, forKey: .layoutBox)
        layoutWidth = try layout.decode(Double.self, forKey: .width)
        layoutHeight = try layout.decode(Double.self, forKey: .height)
    }

    /// 수식 조각에 적용할 가로·세로 배율. 엔진 SVG 렌더러(`RenderNodeType::Equation`)의 규칙이다.
    /// 가로는 항상 저장 상자 너비에 맞추고, 세로는 기본 글자보다 낮은 압축 프레임에서만 맞춘다(일반 수식의 상자
    /// 높이는 줄 여백을 포함하므로 늘이지 않는다).
    public var contentScale: (x: Double, y: Double) {
        let scaleX = layoutWidth > 0 && bbox.width > 0 ? bbox.width / layoutWidth : 1
        let compressed = bbox.height > 0 && bbox.height < fontSize && layoutHeight > 0
        return (scaleX, compressed ? bbox.height / layoutHeight : 1)
    }
}

/// 밑줄·취소선·강조점. 글자 run과 같은 위치·폭(`positions`)을 따라 그린다.
///
/// 엔진은 장식을 `textRun`의 스타일에도 싣지만 **그리기는 이 op가 맡는다**(트림된 줄 끝 공백, 모양 13종, 회전).
/// 렌더러가 둘 다 그리면 이중선이 되므로 텍스트 스타일의 밑줄·취소선은 그리지 않는다.
public struct TextDecorationOp: Sendable, Equatable, Decodable {
    public enum Kind: String, Sendable, Equatable, Decodable {
        case underline, strikethrough, emphasisDot
    }

    public var bbox: LayerRect
    public var kind: Kind
    /// run 원점(bbox 왼쪽 위)에서 기준선까지의 거리.
    public var baseline: Double
    public var rotation: Double
    public var isVertical: Bool
    public var fontSize: Double
    public var ratio: Double
    public var color: LayerColor
    /// 선 모양(한컴 값): 0 실선, 1 파선, 2 점선, 3 일점쇄선, 4 이점쇄선, 5 긴파선, 6 원형점선, 7 이중선,
    /// 8 가는+굵은, 9 굵은+가는, 10 삼중선, 11 물결, 12 이중물결.
    public var shape: Int
    public var underline: UnderlineKind
    /// 강조점 종류(0 없음, 1 ●, 2 ○, 3 ˇ, 4 ˜, 5 ･, 6 ˸).
    public var emphasisDot: Int
    /// 글자별 시작 x(run 원점 기준)와 끝. 줄 끝 공백은 엔진이 이미 걷어냈다.
    public var positions: [Double]

    private enum CodingKeys: String, CodingKey { case bbox, decoration }
    private enum DecorationKeys: String, CodingKey {
        case kind, baseline, rotation, isVertical, fontSize, ratio, color, shape, underline, emphasisDot, positions
    }

    public init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try outer.decode(LayerRect.self, forKey: .bbox)
        let c = try outer.nestedContainer(keyedBy: DecorationKeys.self, forKey: .decoration)
        kind = try c.decode(Kind.self, forKey: .kind)
        baseline = try c.decode(Double.self, forKey: .baseline)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isVertical = try c.decodeIfPresent(Bool.self, forKey: .isVertical) ?? false
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        ratio = try c.decodeIfPresent(Double.self, forKey: .ratio) ?? 1
        color = try c.decode(LayerColor.self, forKey: .color)
        shape = try c.decodeIfPresent(Int.self, forKey: .shape) ?? 0
        underline = try c.decodeIfPresent(UnderlineKind.self, forKey: .underline) ?? .none
        emphasisDot = try c.decodeIfPresent(Int.self, forKey: .emphasisDot) ?? 0
        positions = try c.decode([Double].self, forKey: .positions)
    }
}

/// 탭 리더(채움 기호). 한 줄의 탭마다 시작·끝 x와 채움 모양이 하나씩 온다.
public struct TabLeaderOp: Sendable, Equatable, Decodable {
    public struct Leader: Sendable, Equatable, Decodable {
        public var startX: Double
        public var endX: Double
        /// 채움 모양(한컴 값): 0 없음, 1 실선, 2 파선, 3 점선, 4 일점쇄선, 5 이점쇄선, 6 긴파선, 7 원형점선,
        /// 8 이중실선, 9 가는+굵은, 10 굵은+가는, 11 삼중선.
        public var fillType: Int
    }

    public var bbox: LayerRect
    public var leaders: [Leader]
    public var color: LayerColor
    public var fontSize: Double
    public var baseline: Double
    public var rotation: Double
    public var isVertical: Bool

    private enum CodingKeys: String, CodingKey { case bbox, leaders, color, fontSize, baseline, rotation, isVertical }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        leaders = try c.decode([Leader].self, forKey: .leaders)
        color = try c.decode(LayerColor.self, forKey: .color)
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        baseline = try c.decode(Double.self, forKey: .baseline)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isVertical = try c.decodeIfPresent(Bool.self, forKey: .isVertical) ?? false
    }
}

/// 각주·미주 참조 표식(본문의 위 첨자 번호). `fontSize`는 엔진이 이미 위 첨자 크기로 줄여 보냈다.
public struct FootnoteMarkerOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var text: String
    public var fontFamily: String
    public var fontSize: Double
    public var color: LayerColor
}

/// 그림이 없거나 그릴 수 없는 개체의 자리 표시.
public struct PlaceholderOp: Sendable, Equatable, Decodable {
    public enum Kind: String, Sendable, Equatable, Decodable {
        /// OLE 개체(라벨이 든 상자).
        case ole
        /// 그림 미지정. 한컴의 인쇄 출력에는 나오지 않고 편집 화면에만 보인다.
        case missingPicture
    }

    public var bbox: LayerRect
    public var kind: Kind
    public var fillColor: LayerColor
    public var strokeColor: LayerColor
    public var label: String
}

/// 양식 개체(명령 단추, 선택 상자 등). 엔진이 모양을 이미 도형 조각(`drawing`)으로 풀어 보낸다.
public struct FormObjectOp: Sendable, Equatable, Decodable {
    public enum Primitive: Sendable, Equatable, Decodable {
        case rect(LayerRect, color: LayerColor)
        case circle(x: Double, y: Double, radius: Double, color: LayerColor)
        case polyline(points: [LayerPoint], color: LayerColor, width: Double, closed: Bool)
        case unsupported(kind: String)

        private enum CodingKeys: String, CodingKey { case kind, bbox, color, x, y, radius, points, width, closed }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            switch kind {
            case "rect":
                self = .rect(try c.decode(LayerRect.self, forKey: .bbox), color: try c.decode(LayerColor.self, forKey: .color))
            case "circle":
                self = .circle(
                    x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y),
                    radius: try c.decode(Double.self, forKey: .radius), color: try c.decode(LayerColor.self, forKey: .color)
                )
            case "polyline":
                let pairs = try c.decode([[Double]].self, forKey: .points)
                self = .polyline(
                    points: pairs.compactMap { $0.count == 2 ? LayerPoint(x: $0[0], y: $0[1]) : nil },
                    color: try c.decode(LayerColor.self, forKey: .color),
                    width: try c.decodeIfPresent(Double.self, forKey: .width) ?? 1,
                    closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
                )
            default:
                self = .unsupported(kind: kind)
            }
        }
    }

    /// 단추 이름표 같은 글자. `baseline`은 절대 좌표다.
    public struct Label: Sendable, Equatable, Decodable {
        public var text: String
        public var x: Double
        public var baseline: Double
        public var fontFamily: String
        public var fontSize: Double
        public var bold: Bool
        public var italic: Bool
        public var color: LayerColor
    }

    public var bbox: LayerRect
    public var formType: String
    public var primitives: [Primitive]
    public var label: Label?

    private enum CodingKeys: String, CodingKey { case bbox, formType, drawing }
    private struct Drawing: Decodable {
        let primitives: [Primitive]
        let label: Label?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bbox = try c.decode(LayerRect.self, forKey: .bbox)
        formType = try c.decode(String.self, forKey: .formType)
        let drawing = try c.decode(Drawing.self, forKey: .drawing)
        primitives = drawing.primitives
        label = drawing.label
    }
}

/// 엔진이 만든 SVG 조각(`rect`·`text`·`image`·`line`·`g`). 좌표는 쪽 좌표다.
public struct RawSvgOp: Sendable, Equatable, Decodable {
    public var bbox: LayerRect
    public var svg: String
}

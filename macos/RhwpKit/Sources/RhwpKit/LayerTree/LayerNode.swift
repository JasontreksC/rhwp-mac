import Foundation

/// 한 쪽의 레이어 트리. 렌더러가 소비하는 모든 그리기 정보의 루트다.
public struct PageLayerTree: Sendable, Equatable, Decodable {
    /// 쪽 크기(px, 96dpi).
    public var pageWidth: Double
    public var pageHeight: Double
    public var schemaVersion: Int
    public var schemaMinorVersion: Int
    public var root: LayerNode

    /// 이 모델이 이해하는 스키마 주 버전. 다른 주 버전은 해석하지 않고 실패시킨다.
    public static let supportedSchemaVersion = 1
    /// 이 모델이 가정하는 좌표계. 바뀌면 잘못 그리는 대신 디코딩이 실패해야 한다.
    public static let supportedCoordinateSystem = "page-top-left-y-down"

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, schemaMinorVersion, unit, coordinateSystem, pageWidth, pageHeight, root
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: c,
                debugDescription: "지원하지 않는 레이어 트리 스키마 주 버전: \(schemaVersion)"
            )
        }
        schemaMinorVersion = try c.decodeIfPresent(Int.self, forKey: .schemaMinorVersion) ?? 0

        let coordinateSystem = try c.decode(String.self, forKey: .coordinateSystem)
        guard coordinateSystem == Self.supportedCoordinateSystem else {
            throw DecodingError.dataCorruptedError(
                forKey: .coordinateSystem, in: c,
                debugDescription: "지원하지 않는 좌표계: \(coordinateSystem)"
            )
        }
        let unit = try c.decode(String.self, forKey: .unit)
        guard unit == "px" else {
            throw DecodingError.dataCorruptedError(
                forKey: .unit, in: c, debugDescription: "지원하지 않는 단위: \(unit)"
            )
        }

        pageWidth = try c.decode(Double.self, forKey: .pageWidth)
        pageHeight = try c.decode(Double.self, forKey: .pageHeight)
        root = try c.decode(LayerNode.self, forKey: .root)
    }
}

/// 레이어 트리의 한 노드: 그룹, 잘라내기 영역, 또는 그리기 명령을 담은 잎.
public struct LayerNode: Sendable, Equatable, Decodable {
    public var bounds: LayerRect
    public var content: Content

    public indirect enum Content: Sendable, Equatable {
        /// 자식 노드들의 묶음. 자식은 배열 순서대로 그린다.
        case group(kind: GroupKind, children: [LayerNode])
        /// `clip` 사각형 안에서만 자식이 보인다(표 셀, 글상자, 본문 영역).
        case clip(rect: LayerRect, kind: ClipKind, child: LayerNode)
        /// 실제 그리기 명령들.
        case leaf(ops: [PaintOp])
        /// 이 버전이 모르는 노드 종류. 내용은 버려진다.
        case unsupported(kind: String)
    }

    private enum CodingKeys: String, CodingKey {
        case bounds, kind, groupKind, children, clip, clipKind, child, ops
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bounds = try c.decode(LayerRect.self, forKey: .bounds)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "group":
            content = .group(
                kind: try c.decode(GroupKind.self, forKey: .groupKind),
                children: try c.decode([LayerNode].self, forKey: .children)
            )
        case "clipRect":
            content = .clip(
                rect: try c.decode(LayerRect.self, forKey: .clip),
                kind: try c.decodeIfPresent(ClipKind.self, forKey: .clipKind) ?? .generic,
                child: try c.decode(LayerNode.self, forKey: .child)
            )
        case "leaf":
            content = .leaf(ops: try c.decode([PaintOp].self, forKey: .ops))
        default:
            content = .unsupported(kind: kind)
        }
    }
}

/// 잘라내기 영역의 용도. 알 수 없는 값은 `.generic`.
public enum ClipKind: String, Sendable, Equatable, Decodable {
    case body, tableCell, textBox, generic

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ClipKind(rawValue: raw) ?? .generic
    }
}

/// 그룹의 의미. 렌더러는 몰라도 그릴 수 있지만, 쪽 영역·표·줄 소속을 알아야 하는 소비자(선택, 찾기, 접근성)가 쓴다.
public enum GroupKind: Sendable, Equatable, Decodable {
    case generic, masterPage, header, footer, body, footnoteArea, textBox
    case column(index: Int)
    case textLine(lineHeight: Double, baseline: Double)
    case table(rowCount: Int, colCount: Int, borderFillId: Int)
    case tableCell(TableCellInfo)
    case group(sectionIndex: Int?, paraIndex: Int?, controlIndex: Int?)
    case unknown(kind: String)

    public struct TableCellInfo: Sendable, Equatable, Decodable {
        public var row: Int
        public var col: Int
        public var rowSpan: Int
        public var colSpan: Int
        public var borderFillId: Int
        public var modelCellIndex: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case kind, index, lineHeight, baseline, rowCount, colCount, borderFillId
        case sectionIndex, paraIndex, controlIndex
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "generic": self = .generic
        case "masterPage": self = .masterPage
        case "header": self = .header
        case "footer": self = .footer
        case "body": self = .body
        case "footnoteArea": self = .footnoteArea
        case "textBox": self = .textBox
        case "column":
            self = .column(index: try c.decode(Int.self, forKey: .index))
        case "textLine":
            self = .textLine(
                lineHeight: try c.decode(Double.self, forKey: .lineHeight),
                baseline: try c.decode(Double.self, forKey: .baseline)
            )
        case "table":
            self = .table(
                rowCount: try c.decode(Int.self, forKey: .rowCount),
                colCount: try c.decode(Int.self, forKey: .colCount),
                borderFillId: try c.decode(Int.self, forKey: .borderFillId)
            )
        case "tableCell":
            self = .tableCell(try TableCellInfo(from: decoder))
        case "group":
            self = .group(
                sectionIndex: try c.decodeIfPresent(Int.self, forKey: .sectionIndex),
                paraIndex: try c.decodeIfPresent(Int.self, forKey: .paraIndex),
                controlIndex: try c.decodeIfPresent(Int.self, forKey: .controlIndex)
            )
        default:
            self = .unknown(kind: kind)
        }
    }
}

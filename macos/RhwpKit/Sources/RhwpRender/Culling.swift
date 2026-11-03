import CoreGraphics
import Foundation
import RhwpKit

/// 타일 하나를 그릴 때 그 타일과 겹치지 않는 op를 건너뛰기 위한 범위 계산.
///
/// 타일은 쪽의 작은 조각이라, 트리의 모든 op를 CoreText로 다시 배치하면(특히 글자) 타일 수만큼 일이 곱해진다.
/// CoreGraphics가 타일 밖 픽셀을 버려 주므로 **건너뛰지 않아도 결과는 같다**. 이 파일은 순전히 비용을 줄이는 일이고,
/// 그래서 원칙이 하나다: **모르면 그린다.** 건너뛰는 쪽이 틀리면 타일 경계에서 그림이 잘려 보이므로, 범위는 늘 넉넉하게
/// 잡고 판단할 수 없는 op(회전·세로쓰기 글자, 알 수 없는 op)는 건너뛰지 않는다.
///
/// 건너뛰어도 되는 근거는 둘뿐이다.
/// - `clipRect` 노드: 자식은 그 사각형 **안에서만** 보인다(렌더러가 그렇게 자른다). 엔진의 `bounds` 필드와 무관한 사실이다.
/// - 잎 op: op가 실제로 먹을 칠할 수 있는 범위를 op의 그리기 매개변수에서 보수적으로 잡는다.
///
/// 그룹의 `bounds`는 쓰지 않는다. 엔진이 렌더 트리 노드의 bbox를 그대로 싣는 것이라 자식이 그 안에 있다는 보장이 없다.
enum Culling {
    /// op의 bbox 바깥으로 번질 수 있는 거리(쪽 px). 수식·원본 SVG·양식의 안티앨리어싱과 글리프·선 끝의 번짐을 덮는다.
    static let margin: Double = 24

    /// 두 사각형이 겹치거나 닿는가. 닿는 것까지 겹침으로 보고, NaN이 섞이면 겹친다고 답한다(모르면 그린다).
    static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        !(a.maxX < b.minX || a.minX > b.maxX || a.maxY < b.minY || a.minY > b.maxY)
    }

    /// `region`(쪽 px)에 칠할 수 있는 op인가.
    static func mayDraw(_ op: PaintOp, in region: CGRect) -> Bool {
        guard let extent = extent(of: op) else { return true }
        return overlaps(extent, region)
    }

    /// op가 칠할 수 있는 범위. 판단할 수 없으면 nil(건너뛰지 않는다).
    static func extent(of op: PaintOp) -> CGRect? {
        switch op {
        case let .pageBackground(op):
            return pad(op.bbox.cgRect, by: margin + op.borderWidth)
        case let .textRun(op):
            return textRunExtent(op)
        case let .line(op):
            // 시작·끝 점은 bbox와 따로 오므로 둘 다 덮는다. 선 굵기는 양쪽으로 반씩 번진다(여유를 두 배로).
            var rect = op.bbox.cgRect
            rect = including(op.start.cgPoint, in: rect)
            rect = including(op.end.cgPoint, in: rect)
            return pad(rotationHull(rect, op.transform), by: margin + 2 * op.style.width)
        case let .rectangle(op):
            return pad(rotationHull(op.bbox.cgRect, op.transform), by: margin + 2 * op.style.strokeWidth)
        case let .ellipse(op):
            return pad(rotationHull(op.bbox.cgRect, op.transform), by: margin + 2 * op.style.strokeWidth)
        case let .path(op):
            // 경로 점이 bbox 밖에 있는 입력도 덮는다. 곡선은 제어점의 볼록 껍질 안에 있다.
            var rect = op.bbox.cgRect
            var arcRadius = 0.0
            for command in op.commands {
                switch command {
                case let .moveTo(p), let .lineTo(p):
                    rect = including(p.cgPoint, in: rect)
                case let .curveTo(c1, c2, end):
                    for p in [c1, c2, end] { rect = including(p.cgPoint, in: rect) }
                case let .arcTo(rx, ry, _, _, _, end):
                    rect = including(end.cgPoint, in: rect)
                    arcRadius = max(arcRadius, abs(rx), abs(ry))
                case .closePath, .unsupported:
                    break
                }
            }
            // 타원호는 끝점에서 반지름만큼 벗어날 수 있다.
            let width = max(op.style.strokeWidth, op.lineStyle?.width ?? 0)
            return pad(rotationHull(rect, op.transform), by: margin + 2 * width + 2 * arcRadius)
        case let .image(op):
            return pad(rotationHull(op.bbox.cgRect, op.transform), by: margin)
        case let .equation(op):
            return pad(op.bbox.cgRect, by: margin)
        case let .rawSvg(op):
            return pad(op.bbox.cgRect, by: margin)
        case let .footnoteMarker(op):
            return pad(op.bbox.cgRect, by: margin)
        case let .placeholder(op):
            return pad(op.bbox.cgRect, by: margin)
        case let .formObject(op):
            return pad(op.bbox.cgRect, by: margin)
        case let .textDecoration(op):
            // 회전·세로쓰기 글자의 장식선은 이 렌더러가 그리지 않지만, 판단하지 않고 그린다.
            guard op.rotation == 0, !op.isVertical else { return nil }
            return pad(op.bbox.cgRect, by: margin)
        case let .tabLeader(op):
            guard op.rotation == 0, !op.isVertical else { return nil }
            return pad(op.bbox.cgRect, by: margin)
        case .unsupported:
            return nil
        }
    }

    /// 글자 run이 칠할 수 있는 범위.
    ///
    /// bbox를 믿지 않고 렌더러가 실제로 쓰는 값(원점, 글자 위치, 글자 크기, 장평)에서 구한 범위와 bbox의 합집합이다.
    /// 글리프 한 자는 가로로 글자 크기의 몇 배를 넘지 않고(장평은 가로 배율), 세로로는 기준선 위 1.5em·아래 1em 안에 든다.
    private static func textRunExtent(_ op: TextRunOp) -> CGRect? {
        guard op.rotation == 0, !op.isVertical else { return nil }
        let size = op.style.fontSize
        let positions = op.positions
        guard size.isFinite, size > 0, let first = positions.min(), let last = positions.max() else {
            return pad(op.bbox.cgRect, by: margin)
        }
        let originX = op.runToPage.e
        let baseline = op.runToPage.f
        let reach = 2 * size * max(op.style.ratio, 1)
        let drawn = CGRect(
            x: originX + first - size, y: baseline - 1.5 * size,
            width: (last - first) + size + reach, height: 2.5 * size
        )
        return pad(drawn.union(op.bbox.cgRect), by: 2)
    }

    /// 회전·뒤집기가 있으면 bbox 중심을 지나는 반지름이 대각선의 절반인 정사각형(어떤 각도로 돌려도 이 안에 든다).
    private static func rotationHull(_ rect: CGRect, _ transform: ShapeTransform) -> CGRect {
        guard !transform.isIdentity else { return rect }
        let radius = (rect.width * rect.width + rect.height * rect.height).squareRoot() / 2
        return CGRect(x: rect.midX - radius, y: rect.midY - radius, width: 2 * radius, height: 2 * radius)
    }

    /// 점을 포함하도록 넓힌 사각형. `CGRect.union`이 크기 0인 사각형을 어떻게 다루는지에 기대지 않는다.
    private static func including(_ point: CGPoint, in rect: CGRect) -> CGRect {
        let minX = min(rect.minX, point.x)
        let minY = min(rect.minY, point.y)
        return CGRect(x: minX, y: minY, width: max(rect.maxX, point.x) - minX, height: max(rect.maxY, point.y) - minY)
    }

    private static func pad(_ rect: CGRect, by amount: Double) -> CGRect {
        rect.insetBy(dx: -amount, dy: -amount)
    }
}

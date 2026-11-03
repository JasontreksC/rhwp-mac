import CoreGraphics
import Foundation
import RhwpKit

/// 밑줄·취소선·강조점·탭 리더.
///
/// 엔진은 이 장식들을 글자 run과 **별도 op**로 낸다(`textDecoration`, `tabLeader`). 글자 run의 스타일에는 같은
/// 정보가 남아 있지만 그것은 옛 경로의 거울일 뿐이므로 `drawTextRun`은 장식을 그리지 않는다. 둘 다 그리면 선이
/// 두 번 그려진다.
///
/// 기하 규칙(기준선 아래 0.17em, 다중선 표, 파선 간격, 물결, 탭 리더 12종)은 엔진의 SVG 렌더러
/// (`draw_line_shape`, `draw_text_positioned`)와 `src/renderer/text_decoration.rs`의 한글 2022 실측 계약을 옮긴
/// 것이다. 규칙이 두 곳에 있는 **중복 위험**이 있으니 엔진 쪽이 바뀌면 여기도 고친다.
extension Drawing {
    // MARK: - 글자 장식

    mutating func drawTextDecoration(_ op: TextDecorationOp) {
        // 세로쓰기 글자의 장식은 가로 기준선 규칙을 그대로 쓸 수 없다. 대조 자료가 없어 그리지 않고 집계한다.
        guard !op.isVertical else {
            report.countSkipped("op:textDecoration(vertical)")
            return
        }
        ctx.saveGState()
        applyTextRotation(op.rotation, about: op.bbox.cgRect)

        let x = op.bbox.x
        let baseline = op.bbox.y + op.baseline
        let width = Self.decorationWidth(positions: op.positions, layoutWidth: op.bbox.width)
        let size = op.fontSize
        let color = op.color.cgColor

        switch op.kind {
        case .underline:
            switch op.underline {
            case .none:
                break
            case .top:
                strokeLineShape(x: x, y: baseline - size + 1, width: width, color: color, shape: op.shape)
            case .bottom:
                if let lines = Self.underlineMultiLines[op.shape] {
                    // 이중·삼중 밑줄은 선별 위치와 굵기가 글자 크기에 비례한다(한글 2022 실측표).
                    for (offset, thickness) in lines {
                        strokeSegment(
                            x, x + width, baseline + size * offset, width: max(size * thickness, 0.3),
                            dash: [], cap: .butt, color: color
                        )
                    }
                } else {
                    strokeLineShape(x: x, y: baseline + size * Self.underlineBaselineRatio, width: width, color: color, shape: op.shape)
                }
            }
        case .strikethrough:
            strokeLineShape(x: x, y: baseline - size * 0.3, width: width, color: color, shape: op.shape)
        case .emphasisDot:
            drawEmphasisDots(op, originX: x, baseline: baseline, size: size)
        }
        ctx.restoreGState()
        report.countRendered("op:textDecoration")
    }

    /// 장식선의 폭. 줄 끝 공백을 걷어내지 않은 run은 **배치 폭**(bbox)을 그대로 쓰고, 걷어냈다면 글자 위치의
    /// 끝을 쓴다. 엔진은 트림이 없을 때 작성기 측정과 배치 폭이 0.3px쯤 어긋나 조각 사이에 틈이 생기는 문제
    /// (#6451)를 피하려고 배치 폭을 쓴다. op에는 트림 개수가 없으므로 두 값이 0.5px 이내면 트림이 없는 것으로
    /// 본다 — 걷어낸 공백은 한 글자 폭(수 px)이라 이 문턱과 섞이지 않는다.
    static func decorationWidth(positions: [Double], layoutWidth: Double) -> Double {
        let end = positions.last ?? 0
        return abs(end - layoutWidth) <= 0.5 ? layoutWidth : end
    }

    private static let underlineBaselineRatio = 0.17

    /// 밑줄 다중선(shape 7~10)의 (기준선 아래 오프셋 em, 선 굵기 em). `text_decoration.rs`의 표다.
    private static let underlineMultiLines: [Int: [(Double, Double)]] = [
        7: [(0.160, 0.032), (0.250, 0.032)],
        8: [(0.175, 0.048), (0.300, 0.100)],
        9: [(0.200, 0.100), (0.325, 0.048)],
        10: [(0.165, 0.032), (0.250, 0.080), (0.335, 0.032)],
    ]

    private mutating func drawEmphasisDots(_ op: TextDecorationOp, originX: Double, baseline: Double, size: Double) {
        let glyph: String
        switch op.emphasisDot {
        case 1: glyph = "●"
        case 2: glyph = "○"
        case 3: glyph = "ˇ"
        case 4: glyph = "˜"
        case 5: glyph = "･"
        case 6: glyph = "˸"
        default: return
        }
        // 글자마다 하나씩, 글자 위(기준선 위 1.05em)에 글자 폭의 가운데로 찍는다. 마지막 위치는 run의 끝이다.
        for position in op.positions.dropLast() {
            drawString(
                glyph, x: originX + position + size * op.ratio * 0.5, baseline: baseline - size * 1.05,
                family: "sans-serif", size: size * 0.3, bold: false, italic: false, color: op.color, anchor: .middle
            )
        }
    }

    // MARK: - 탭 리더

    mutating func drawTabLeader(_ op: TabLeaderOp) {
        guard !op.isVertical else {
            report.countSkipped("op:tabLeader(vertical)")
            return
        }
        ctx.saveGState()
        applyTextRotation(op.rotation, about: op.bbox.cgRect)
        let color = op.color.cgColor
        // 글자 세로 중앙(기준선에서 x-height의 절반쯤).
        let y = op.bbox.y + op.baseline - op.fontSize * 0.35
        for leader in op.leaders where leader.fillType != 0 {
            drawLeader(
                fillType: leader.fillType, x1: op.bbox.x + leader.startX, x2: op.bbox.x + leader.endX, y: y,
                fontSize: op.fontSize, color: color
            )
        }
        ctx.restoreGState()
        report.countRendered("op:tabLeader")
    }

    /// 채움 12종: 1 실선, 2 파선, 3 점선, 4 일점쇄선, 5 이점쇄선, 6 긴파선, 7 원형점선, 8 이중실선,
    /// 9 얇고 굵은 이중선, 10 굵고 얇은 이중선, 11 얇고 굵고 얇은 삼중선. 그 밖은 점선으로 대신한다.
    private func drawLeader(fillType: Int, x1: Double, x2: Double, y: Double, fontSize: Double, color: CGColor) {
        switch fillType {
        case 1: strokeSegment(x1, x2, y, width: 0.5, dash: [], cap: .butt, color: color)
        case 2: strokeSegment(x1, x2, y, width: 0.5, dash: [3, 3], cap: .butt, color: color)
        case 3:
            // 점선은 글자 크기에 비례하는 둥근 점이다(한컴의 목차 점선). 두께·간격 상수는 엔진의
            // `tab_dot_leader_stroke`와 같다: 지름 0.12em, 피치 0.248em.
            let thickness = fontSize * 0.12
            let pitch = fontSize * 0.248
            let dash = min(0.1, pitch * 0.5)
            strokeSegment(x1, x2, y, width: thickness, dash: [dash, max(pitch - dash, 0.1)], cap: .round, color: color)
        case 4: strokeSegment(x1, x2, y, width: 0.5, dash: [6, 2, 1, 2], cap: .butt, color: color)
        case 5: strokeSegment(x1, x2, y, width: 0.5, dash: [6, 2, 1, 2, 1, 2], cap: .butt, color: color)
        case 6: strokeSegment(x1, x2, y, width: 0.5, dash: [8, 4], cap: .butt, color: color)
        case 7: strokeSegment(x1, x2, y, width: 0.7, dash: [0.1, 2.5], cap: .round, color: color)
        case 8:
            strokeSegment(x1, x2, y - 1, width: 0.3, dash: [], cap: .butt, color: color)
            strokeSegment(x1, x2, y + 1, width: 0.3, dash: [], cap: .butt, color: color)
        case 9:
            strokeSegment(x1, x2, y - 1.2, width: 0.3, dash: [], cap: .butt, color: color)
            strokeSegment(x1, x2, y + 0.8, width: 0.8, dash: [], cap: .butt, color: color)
        case 10:
            strokeSegment(x1, x2, y - 0.8, width: 0.8, dash: [], cap: .butt, color: color)
            strokeSegment(x1, x2, y + 1.2, width: 0.3, dash: [], cap: .butt, color: color)
        case 11:
            strokeSegment(x1, x2, y - 2, width: 0.3, dash: [], cap: .butt, color: color)
            strokeSegment(x1, x2, y, width: 0.8, dash: [], cap: .butt, color: color)
            strokeSegment(x1, x2, y + 2, width: 0.3, dash: [], cap: .butt, color: color)
        default:
            strokeSegment(x1, x2, y, width: 0.5, dash: [1, 2], cap: .butt, color: color)
        }
    }

    // MARK: - 선 모양

    /// 가로선 하나를 한컴 선 모양(shape 0~12)대로 긋는다. 엔진의 `draw_line_shape`다.
    /// 0 실선, 1 파선, 2 점선, 3 일점쇄선, 4 이점쇄선, 5 긴파선, 6 원형점선, 7 이중선, 8 가는+굵은, 9 굵은+가는,
    /// 10 삼중선, 11 물결, 12 이중물결.
    private func strokeLineShape(x: Double, y: Double, width: Double, color: CGColor, shape: Int) {
        let x2 = x + width
        switch shape {
        case 7:
            strokeSegment(x, x2, y - 1, width: 0.7, dash: [], cap: .butt, color: color)
            strokeSegment(x, x2, y + 1, width: 0.7, dash: [], cap: .butt, color: color)
        case 8:
            strokeSegment(x, x2, y - 1.2, width: 0.5, dash: [], cap: .butt, color: color)
            strokeSegment(x, x2, y + 0.8, width: 1.2, dash: [], cap: .butt, color: color)
        case 9:
            strokeSegment(x, x2, y - 0.8, width: 1.2, dash: [], cap: .butt, color: color)
            strokeSegment(x, x2, y + 1.2, width: 0.5, dash: [], cap: .butt, color: color)
        case 10:
            for offset in [-1.5, 0, 1.5] { strokeSegment(x, x2, y + offset, width: 0.5, dash: [], cap: .butt, color: color) }
        case 11:
            strokeWave(x, x2, y, amplitude: 1.5, width: 0.7, color: color)
        case 12:
            for offset in [-1.0, 1.0] { strokeWave(x, x2, y + offset, amplitude: 1.2, width: 0.5, color: color) }
        default:
            let dash: [CGFloat]
            var cap = CGLineCap.butt
            switch shape {
            case 1: dash = [3, 3]
            case 2: dash = [1, 2]
            case 3: dash = [6, 2, 1, 2]
            case 4: dash = [6, 2, 1, 2, 1, 2]
            case 5: dash = [8, 4]
            case 6:
                dash = [0.1, 2.5]
                cap = .round
            default: dash = []
            }
            strokeSegment(x, x2, y, width: 1, dash: dash, cap: cap, color: color)
        }
    }

    /// 물결선: 6px마다 위·아래로 번갈아 휘는 2차 곡선을 이어 붙인다.
    private func strokeWave(_ x1: Double, _ x2: Double, _ y: Double, amplitude: Double, width: Double, color: CGColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x1, y: y))
        var current = x1
        var up = true
        while current < x2 {
            let next = min(current + 6, x2)
            path.addQuadCurve(
                to: CGPoint(x: next, y: y),
                control: CGPoint(x: (current + next) / 2, y: up ? y - amplitude : y + amplitude)
            )
            current = next
            up.toggle()
        }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func strokeSegment(
        _ x1: Double, _ x2: Double, _ y: Double, width: Double, dash: [CGFloat], cap: CGLineCap, color: CGColor
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(cap)
        ctx.setLineDash(phase: 0, lengths: dash)
        ctx.move(to: CGPoint(x: x1, y: y))
        ctx.addLine(to: CGPoint(x: x2, y: y))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// 글자 op의 회전은 bbox 중심 기준이다(엔진 `with_layer_text_rotation`).
    private func applyTextRotation(_ degrees: Double, about box: CGRect) {
        guard degrees != 0 else { return }
        ctx.translateBy(x: box.midX, y: box.midY)
        ctx.rotate(by: CGFloat(degrees * .pi / 180))
        ctx.translateBy(x: -box.midX, y: -box.midY)
    }
}

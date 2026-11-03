import CoreGraphics
import Foundation

/// SVG 타원호(`A rx ry rot large sweep x y`)를 3차 베지어로 바꾼다.
///
/// 레이어 트리의 `arcTo`와 SVG 조각의 `A` 명령이 같은 규칙을 쓴다. 규칙은 SVG 1.1 부록 F.6.5의
/// "끝점 매개변수 → 중심 매개변수" 변환이다. 렌더러가 호를 직선으로 근사하면 도넛·파이·둥근 모서리 도형이
/// 모두 틀리므로 4단계에서 정확한 호로 바꿨다.
enum SVGArc {
    /// `start`에서 `end`까지의 호를 `path`에 이어 붙인다. 현재 점은 `start`여야 한다.
    ///
    /// 반지름이 0이거나 시작점과 끝점이 같으면 SVG 규격대로 호를 생략하고 끝점까지 직선을 긋는다(끝점이 같으면
    /// 아무것도 그리지 않는다). 반지름이 두 점을 잇기에 너무 작으면 규격대로 늘린다.
    static func append(
        to path: CGMutablePath, from start: CGPoint, radiusX: Double, radiusY: Double, rotationDegrees: Double,
        largeArc: Bool, sweep: Bool, to end: CGPoint
    ) {
        if start == end { return }
        var rx = abs(radiusX)
        var ry = abs(radiusY)
        guard rx > 0, ry > 0, rx.isFinite, ry.isFinite else {
            path.addLine(to: end)
            return
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // F.6.5.1: 시작-끝 중점을 원점으로 옮기고 타원 축에 맞춰 돌린다.
        let dx = (Double(start.x) - Double(end.x)) / 2
        let dy = (Double(start.y) - Double(end.y)) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // F.6.6: 반지름이 너무 작으면 두 점을 지나는 가장 작은 타원으로 키운다.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rx *= scale
            ry *= scale
        }

        // F.6.5.2: 중심 (cx', cy').
        let rx2 = rx * rx
        let ry2 = ry * ry
        let numerator = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        // 수치 오차로 음수가 되면 0으로 자른다(정확히 반원인 경우).
        var coefficient = denominator == 0 ? 0 : (max(numerator, 0) / denominator).squareRoot()
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * (-ry * x1p / rx)

        // F.6.5.3: 원래 좌표계의 중심.
        let cx = cosPhi * cxp - sinPhi * cyp + (Double(start.x) + Double(end.x)) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (Double(start.y) + Double(end.y)) / 2

        // F.6.5.5~6: 시작 각도와 sweep 각도.
        let startAngle = atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
        let endAngle = atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx)
        var delta = endAngle - startAngle
        if sweep, delta < 0 { delta += 2 * .pi }
        if !sweep, delta > 0 { delta -= 2 * .pi }

        // 90도 이하 조각으로 나눠 각각 3차 베지어로 근사한다.
        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let handle = 4.0 / 3.0 * tan(step / 4)
        var angle = startAngle
        for _ in 0 ..< segments {
            let next = angle + step
            let p0 = unitPoint(angle)
            let p3 = unitPoint(next)
            // 단위원 위의 접선 방향으로 제어점을 둔다.
            let c1 = (x: p0.x - handle * p0.y, y: p0.y + handle * p0.x)
            let c2 = (x: p3.x + handle * p3.y, y: p3.y - handle * p3.x)
            path.addCurve(
                to: map(p3, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, cx: cx, cy: cy),
                control1: map(c1, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, cx: cx, cy: cy),
                control2: map(c2, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, cx: cx, cy: cy)
            )
            angle = next
        }
    }

    private static func unitPoint(_ angle: Double) -> (x: Double, y: Double) { (cos(angle), sin(angle)) }

    /// 단위원 좌표를 타원의 크기·회전·중심으로 옮긴다.
    private static func map(
        _ p: (x: Double, y: Double), rx: Double, ry: Double, cosPhi: Double, sinPhi: Double, cx: Double, cy: Double
    ) -> CGPoint {
        let x = rx * p.x
        let y = ry * p.y
        return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
    }
}

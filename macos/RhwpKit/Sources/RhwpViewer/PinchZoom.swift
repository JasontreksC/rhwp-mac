import CoreGraphics
import Foundation

/// 진행 중인 핀치 확대. 손을 떼기 전까지는 배율(`Zoom`)·배치·타일을 바꾸지 않고, 화면이 지금 보이는 것을 이 배율만큼 늘려
/// 보여 준다(낮은 해상도로 즉시 확대). 손을 떼면 `resultingZoom`으로 정하고 그 배율의 타일을 채운다.
public struct PinchState: Sendable, Equatable {
    /// 제스처가 시작될 때의 배율.
    public let base: Zoom
    /// 제스처가 보고한 확대 비율(1 = 변화 없음)을 허용 범위로 맞춘 값. `base × magnification`이 `Zoom.range` 안에 든다.
    public private(set) var magnification: Double
    /// 두 손가락의 중심(제스처를 받는 뷰의 좌표 = 스크롤 영역 좌표, pt). 확대는 이 점을 붙잡고 일어난다.
    public let anchor: CGPoint

    public init(base: Zoom, magnification: Double = 1, anchor: CGPoint) {
        self.base = base
        self.anchor = anchor
        self.magnification = Self.clamped(magnification, base: base)
    }

    public mutating func update(magnification raw: Double) {
        magnification = Self.clamped(raw, base: base)
    }

    /// 손을 떼면 정해질 배율.
    public var resultingZoom: Zoom { Zoom(base.factor * magnification) }

    /// 확대 비율을 `base × 비율`이 허용 범위 안에 들도록 맞춘다. 유한하지 않거나 0 이하면 1(변화 없음)이다.
    ///
    /// 범위를 넘어서까지 늘이면 손을 뗄 때 화면이 갑자기 줄어든다(눈에 보이던 배율이 사실은 허용되지 않던 값이었으므로).
    /// 그래서 미리보기 단계에서부터 같은 범위로 막는다.
    public static func clamped(_ raw: Double, base: Zoom) -> Double {
        guard raw.isFinite, raw > 0 else { return 1 }
        let low = Zoom.range.lowerBound / base.factor
        let high = Zoom.range.upperBound / base.factor
        return min(max(raw, low), high)
    }
}

import Foundation

/// 뷰어의 확대 배율. 1.0이 100%(쪽 크기 그대로, 96dpi px를 화면 pt 1:1로 본 크기)다.
///
/// 배율은 항상 `range` 안으로 맞춰진다. 확대·축소는 아래 `steps`의 다음 단계로 움직여서, 사용자가 어떤
/// 배율에 있든(맞춤 배율처럼 단계에 없는 값 포함) 한 번 누르면 눈에 보이게 달라진다.
public struct Zoom: Sendable, Equatable, Hashable {
    public static let range: ClosedRange<Double> = 0.25...4.0
    public static let steps: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
    public static let actualSize = Zoom(1.0)

    public let factor: Double

    /// 범위 밖의 값은 가장 가까운 끝으로 맞추고, 유한하지 않은 값(NaN, 무한대)은 100%로 둔다.
    public init(_ factor: Double) {
        self.factor = factor.isFinite ? min(max(factor, Self.range.lowerBound), Self.range.upperBound) : 1.0
    }

    /// 지금보다 큰 다음 단계. 이미 끝이면 그대로다.
    public func zoomedIn() -> Zoom {
        // 부동소수 오차로 같은 단계를 다시 고르지 않도록 작은 여유를 둔다.
        Zoom(Self.steps.first { $0 > factor + 1e-9 } ?? Self.range.upperBound)
    }

    /// 지금보다 작은 다음 단계. 이미 끝이면 그대로다.
    public func zoomedOut() -> Zoom {
        Zoom(Self.steps.last { $0 < factor - 1e-9 } ?? Self.range.lowerBound)
    }

    public var canZoomIn: Bool { factor < Self.range.upperBound - 1e-9 }
    public var canZoomOut: Bool { factor > Self.range.lowerBound + 1e-9 }

    /// "125%" 같은 표시. 소수 퍼센트는 반올림한다.
    public var percentLabel: String { "\(Int((factor * 100).rounded()))%" }

    /// 쪽 너비가 보이는 영역에 꼭 맞는 배율. `availableWidth`는 좌우 여백을 뺀 너비(pt)다.
    public static func fitWidth(availableWidth: Double, pageWidth: Double) -> Zoom {
        guard availableWidth > 0, pageWidth > 0 else { return .actualSize }
        return Zoom(availableWidth / pageWidth)
    }

    /// 쪽 전체가 보이는 영역에 들어가는 배율.
    public static func fitPage(availableWidth: Double, availableHeight: Double, pageWidth: Double, pageHeight: Double) -> Zoom {
        guard availableWidth > 0, availableHeight > 0, pageWidth > 0, pageHeight > 0 else { return .actualSize }
        return Zoom(min(availableWidth / pageWidth, availableHeight / pageHeight))
    }
}

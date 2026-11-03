import CoreGraphics
import Foundation

/// 스크롤 영역 가장자리에서 도구 막대·떠 있는 사이드바 같은 시스템 막이 가리는 폭(pt).
///
/// macOS 26의 상세 화면은 도구 막대와 사이드바 **아래까지** 이어지고(Liquid Glass가 그 위에 얹힌다) 그만큼 내용 인셋이 붙는다.
/// 가려진 영역도 유리 너머로 비치므로 타일은 그곳까지 그리지만, 사용자가 "보고 있다"고 느끼는 영역(확대 앵커, 위에 걸린 쪽,
/// 너비 맞춤)은 가려지지 않은 영역이다.
public struct ViewportInsets: Sendable, Equatable {
    public var leading: Double
    public var top: Double
    public var trailing: Double
    public var bottom: Double

    public static let zero = ViewportInsets(leading: 0, top: 0, trailing: 0, bottom: 0)

    public init(leading: Double, top: Double, trailing: Double, bottom: Double) {
        self.leading = leading
        self.top = top
        self.trailing = trailing
        self.bottom = bottom
    }
}

/// 스크롤 영역이 지금 보여 주는 곳. 좌표는 스크롤 내용의 왼쪽 위가 원점이다(pt).
///
/// 화면(SwiftUI)이 스크롤 지오메트리에서 읽어 모델에 알린다. 어느 타일을 그릴지, 확대할 때 어디를 붙잡고 있을지가 이 값에서 정해진다.
/// `offset`과 `size`는 **가려지지 않은** 영역이다. 스크롤 지오메트리의 `contentOffset`은 인셋만큼 음수에서 시작하므로
/// (쉴 때 (−사이드바 폭, −도구 막대 높이)) 화면이 인셋을 더해서 넘긴다. 내용 맨 위를 보고 있으면 offset은 (0, 0)이다.
public struct Viewport: Sendable, Equatable {
    /// 가려지지 않은 영역의 왼쪽 위(스크롤 내용 좌표).
    public var offset: CGPoint
    /// 가려지지 않은 영역의 크기.
    public var size: CGSize
    /// 시스템 막이 가리는 폭.
    public var insets: ViewportInsets

    public static let zero = Viewport(offset: .zero, size: .zero)

    public init(offset: CGPoint, size: CGSize, insets: ViewportInsets = .zero) {
        self.offset = offset
        self.size = size
        self.insets = insets
    }

    /// 화면에 닿는 내용 영역(가려진 곳 포함). 어느 타일을 그릴지 정할 때 쓴다. 크기를 모르면(아직 보고되지 않았으면) 비어 있다.
    public var visibleRect: CGRect {
        CGRect(
            x: offset.x - insets.leading, y: offset.y - insets.top,
            width: size.width + insets.leading + insets.trailing, height: size.height + insets.top + insets.bottom
        )
    }

    /// 크기가 알려졌는가. 첫 지오메트리 보고 전에는 false 다.
    public var isKnown: Bool { size.width > 0 && size.height > 0 }
}

/// 모델이 화면에 요청하는 스크롤. `serial`이 늘어날 때마다 새 요청이다(같은 위치를 다시 요청해도 화면이 알아챈다).
public struct ScrollRequest: Sendable, Equatable {
    public var offset: CGPoint
    public var serial: Int
}

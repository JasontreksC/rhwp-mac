import CoreGraphics
import Foundation

/// 스크롤 영역이 지금 보여 주는 곳. 좌표는 스크롤 내용의 왼쪽 위가 원점이다(pt).
///
/// 화면(SwiftUI)이 스크롤 지오메트리에서 읽어 모델에 알린다. 어느 타일을 그릴지, 확대할 때 어디를 붙잡고 있을지가 이 값에서 정해진다.
public struct Viewport: Sendable, Equatable {
    /// 보이는 영역의 왼쪽 위(스크롤 내용 좌표).
    public var offset: CGPoint
    /// 보이는 영역의 크기.
    public var size: CGSize

    public static let zero = Viewport(offset: .zero, size: .zero)

    public init(offset: CGPoint, size: CGSize) {
        self.offset = offset
        self.size = size
    }

    /// 화면에 보이는 내용 영역. 크기를 모르면(아직 보고되지 않았으면) 비어 있다.
    public var visibleRect: CGRect { CGRect(origin: offset, size: size) }

    /// 크기가 알려졌는가. 첫 지오메트리 보고 전에는 false 다.
    public var isKnown: Bool { size.width > 0 && size.height > 0 }
}

/// 모델이 화면에 요청하는 스크롤. `serial`이 늘어날 때마다 새 요청이다(같은 위치를 다시 요청해도 화면이 알아챈다).
public struct ScrollRequest: Sendable, Equatable {
    public var offset: CGPoint
    public var serial: Int
}

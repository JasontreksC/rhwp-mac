import Foundation

/// 한 쪽의 크기. 단위는 px(96dpi)이고 레이어 트리의 `pageWidth/pageHeight`와 같은 값이다.
///
/// 쪽 그림을 받기 전에 스크롤 영역과 썸네일 자리를 잡는 데 쓴다. 쪽마다 크기가 다를 수 있다
/// (구역마다 용지 방향·크기가 다른 문서).
public struct PageSize: Sendable, Equatable, Decodable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

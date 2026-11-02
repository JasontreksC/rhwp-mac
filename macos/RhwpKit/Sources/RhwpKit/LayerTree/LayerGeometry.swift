import Foundation

// 레이어 트리의 기하 값 타입. 좌표계는 `page-top-left-y-down`, 단위는 px(96dpi)다.
// 플랫폼 그래픽 타입(CGRect 등)에 묶지 않는다 — 변환은 렌더러가 한다.

public struct LayerRect: Sendable, Equatable, Decodable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct LayerPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 2차원 아핀 변환 `(a b c d e f)`. 점 (x, y)는 (a·x + c·y + e, b·x + d·y + f)로 옮겨진다.
public struct LayerAffine: Sendable, Equatable, Decodable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var e: Double
    public var f: Double
}

/// 도형 회전·뒤집기. 회전 중심은 도형의 bbox 중심이고 단위는 도(degree)다.
public struct ShapeTransform: Sendable, Equatable, Decodable {
    public var rotation: Double
    public var horzFlip: Bool
    public var vertFlip: Bool

    public static let identity = ShapeTransform(rotation: 0, horzFlip: false, vertFlip: false)

    public var isIdentity: Bool { self == .identity }
}

/// `#rrggbb` 색. 알파는 없다(엔진이 투명도를 `opacity` 필드로 따로 싣는다).
public struct LayerColor: Sendable, Equatable, Hashable, Decodable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `#rrggbb`(소문자·대문자 모두)만 받는다. 그 밖의 형식은 nil.
    public init?(cssHex: String) {
        guard cssHex.utf8.count == 7, cssHex.hasPrefix("#"),
              let value = UInt32(cssHex.dropFirst(), radix: 16)
        else { return nil }
        self.init(
            red: UInt8((value >> 16) & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8(value & 0xFF)
        )
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = LayerColor(cssHex: text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "#rrggbb 형식이 아닌 색: \(text)")
            )
        }
        self = color
    }
}

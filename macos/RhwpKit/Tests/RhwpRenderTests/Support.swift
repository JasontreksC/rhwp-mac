import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender
import Testing

/// 시험 입력. 파일이 없으면 건너뛰지 않고 실패시킨다(조용한 통과로 검사 0건이 되는 것을 막는다).
enum Fixtures {
    /// 저장소 루트: Tests/RhwpRenderTests/<이 파일> → RhwpRenderTests → Tests → RhwpKit → macos → 저장소.
    static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static func openSession(_ name: String) async throws -> RhwpDocumentSession {
        let url = repoRoot.appendingPathComponent("samples").appendingPathComponent(name)
        try #require(FileManager.default.fileExists(atPath: url.path), "샘플 파일 없음: \(url.path)")
        return try await RhwpDocumentSession.open(contentsOf: url)
    }
}

/// 손으로 쓴 작은 레이어 트리. 엔진 출력에 기대지 않고 기대 픽셀을 직접 정하기 위한 것이다.
func makeTree(_ rootJSON: String, width: Int = 100, height: Int = 100) throws -> PageLayerTree {
    let json = """
    {"schemaVersion":1,"schemaMinorVersion":0,"unit":"px","coordinateSystem":"page-top-left-y-down",
     "pageWidth":\(width),"pageHeight":\(height),"root":\(rootJSON)}
    """
    return try JSONDecoder().decode(PageLayerTree.self, from: Data(json.utf8))
}

/// 잎 하나에 op들을 담은 트리.
func makeLeafTree(ops: [String], width: Int = 100, height: Int = 100) throws -> PageLayerTree {
    try makeTree(leaf(ops: ops, width: width, height: height), width: width, height: height)
}

func leaf(ops: [String], width: Int = 100, height: Int = 100) -> String {
    #"{"kind":"leaf","bounds":{"x":0,"y":0,"width":\#(width),"height":\#(height)},"ops":[\#(ops.joined(separator: ","))]}"#
}

enum OpJSON {
    static func background(_ color: String = "#ffffff", size: Int = 100) -> String {
        #"{"type":"pageBackground","bbox":{"x":0,"y":0,"width":\#(size),"height":\#(size)},"backgroundColor":"\#(color)"}"#
    }

    static func style(fill: String?, stroke: String? = nil, width: Double = 0, opacity: Double = 1) -> String {
        let fillJSON = fill.map { "\"\($0)\"" } ?? "null"
        let strokeJSON = stroke.map { "\"\($0)\"" } ?? "null"
        return #"{"fillColor":\#(fillJSON),"strokeColor":\#(strokeJSON),"strokeWidth":\#(width),"strokeDash":"solid","opacity":\#(opacity)}"#
    }

    static func rectangle(x: Int, y: Int, w: Int, h: Int, fill: String, gradient: String? = nil) -> String {
        let gradientJSON = gradient.map { #","gradient":\#($0)"# } ?? ""
        return #"{"type":"rectangle","bbox":{"x":\#(x),"y":\#(y),"width":\#(w),"height":\#(h)},"style":\#(style(fill: fill))\#(gradientJSON)}"#
    }

    static func linearGradient(angle: Int, from: String, to: String) -> String {
        #"{"gradientType":1,"angle":\#(angle),"centerX":50,"centerY":50,"colors":["\#(from)","\#(to)"],"positions":[0,1]}"#
    }

    static func textRun(_ text: String, font: String, size: Double, originX: Double, baseline: Double, positions: [Double]) -> String {
        let pos = positions.map { String($0) }.joined(separator: ",")
        return #"""
        {"type":"textRun","bbox":{"x":\#(originX),"y":\#(baseline - size),"width":50,"height":\#(size)},"text":"\#(text)","baseline":\#(size),
         "placement":{"runToPage":{"a":1,"b":0,"c":0,"d":1,"e":\#(originX),"f":\#(baseline)}},"positions":[\#(pos)],
         "style":{"fontFamily":"\#(font)","fontSize":\#(size),"color":"#000000"}}
        """#
    }
}

/// 렌더링 결과 비트맵의 픽셀을 읽는다. 좌표는 이미지 왼쪽 위가 원점이다.
struct Pixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = data
    }

    /// `region`(작은 비트맵)이 이 비트맵의 (x, y)에서 시작하는 같은 크기 영역과 얼마나 다른지 잰다.
    /// 채널(RGBA) 값이 다른 픽셀 수, 가장 큰 채널 차이, 처음 어긋난 위치(이 비트맵 좌표)를 돌려준다. 같으면 (0, 0, nil)이다.
    func compare(_ region: Pixels, atX x: Int, y: Int) -> (differing: Int, maxDelta: Int, first: (x: Int, y: Int)?) {
        var differing = 0
        var maxDelta = 0
        var first: (x: Int, y: Int)?
        for row in 0..<region.height {
            for column in 0..<region.width {
                let mine = ((y + row) * width + x + column) * 4
                let theirs = (row * region.width + column) * 4
                var delta = 0
                for channel in 0..<4 { delta = max(delta, abs(Int(bytes[mine + channel]) - Int(region.bytes[theirs + channel]))) }
                if delta > 0 {
                    differing += 1
                    maxDelta = max(maxDelta, delta)
                    if first == nil { first = (x + column, y + row) }
                }
            }
        }
        return (differing, maxDelta, first)
    }

    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// 흰색이 아닌 픽셀의 가로 범위. 없으면 nil.
    func inkColumns() -> ClosedRange<Int>? {
        var low: Int?
        var high: Int?
        for y in 0..<height {
            for x in 0..<width where rgb(x, y) != (255, 255, 255) {
                low = min(low ?? x, x)
                high = max(high ?? x, x)
            }
        }
        guard let low, let high else { return nil }
        return low...high
    }
}

/// 트리를 훑어 모든 op 개수를 센다(렌더러의 집계와 독립적인 기준).
func countOps(_ node: LayerNode) -> Int {
    switch node.content {
    case let .group(_, children): children.reduce(0) { $0 + countOps($1) }
    case let .clip(_, _, child): countOps(child)
    case let .leaf(ops): ops.count
    case .unsupported: 0
    }
}

func isNear(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int), tolerance: Int = 3) -> Bool {
    abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
}

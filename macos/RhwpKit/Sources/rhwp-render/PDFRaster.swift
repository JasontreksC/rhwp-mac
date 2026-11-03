import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 한컴이 출력한 기준 PDF를 흰 배경 PNG로 래스터한다.
///
/// 시각 검증은 같은 쪽의 PDF 래스터와 우리 렌더러의 출력을 비교한다. 두 그림이 같은 좌표계·배율이어야 하므로 배율 1은
/// 96dpi(PDF 1pt = 1.333px)로 우리 레이어 트리의 px 단위와 맞춘다. PDF는 투명 배경이라 흰 종이 위에 그린다
/// (그러지 않으면 투명 영역이 검게 읽혀 일치율이 무의미해진다).
enum PDFRaster {
    enum Failure: Error, CustomStringConvertible {
        case unreadable(String)
        case encodingFailed(page: Int)

        var description: String {
            switch self {
            case let .unreadable(path): "PDF를 읽을 수 없음: \(path)"
            case let .encodingFailed(page): "\(page)쪽 PNG 인코딩 실패"
            }
        }
    }

    /// PDF의 총 쪽수.
    static func pageCount(of url: URL) throws -> Int {
        guard let document = CGPDFDocument(url as CFURL) else { throw Failure.unreadable(url.path) }
        return document.numberOfPages
    }

    /// 선택한 쪽(1부터)을 `page-001.png` 형식으로 `directory`에 저장한다. 저장한 쪽 수를 돌려준다.
    static func render(
        pdf url: URL, pages: PageSelection?, scale: Double, into directory: URL
    ) throws -> (total: Int, saved: Int) {
        guard let document = CGPDFDocument(url as CFURL) else { throw Failure.unreadable(url.path) }
        let total = document.numberOfPages
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var saved = 0
        for number in 1...max(total, 1) where total > 0 && (pages?.contains(number) ?? true) {
            guard let page = document.page(at: number) else { continue }
            let box = page.getBoxRect(.cropBox)
            let factor = scale * 96 / 72
            let width = Int((box.width * factor).rounded())
            let height = Int((box.height * factor).rounded())
            guard width > 0, height > 0, width <= 16384, height <= 16384,
                  let context = CGContext(
                      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { continue }
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: factor, y: factor)
            // 쪽 회전과 CropBox 원점을 PDF 쪽이 정한 대로 맞춘다.
            context.concatenate(page.getDrawingTransform(
                .cropBox, rect: CGRect(x: 0, y: 0, width: box.width, height: box.height), rotate: 0, preserveAspectRatio: true
            ))
            context.drawPDFPage(page)
            guard let image = context.makeImage() else { throw Failure.encodingFailed(page: number) }
            try write(image, to: directory.appendingPathComponent(String(format: "page-%03d.png", number)), page: number)
            saved += 1
        }
        return (total, saved)
    }

    private static func write(_ image: CGImage, to url: URL, page: Int) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.encodingFailed(page: page) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed(page: page) }
    }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension RenderedPage {
    /// 비트맵을 PNG 데이터로 인코딩한다. 인코딩할 수 없으면 nil.
    public func pngData() -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

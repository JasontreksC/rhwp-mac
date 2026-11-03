import CoreGraphics
import RhwpViewer
import SwiftUI

/// 쪽 하나의 그림. 화면에 나타나는 동안만 그림을 받고, 도착하기 전에는 흰 종이를 보여 준다.
///
/// 크기는 호출자가 정한다(쪽 배치가 그림보다 먼저 정해지므로 그림이 늦어도 스크롤 길이가 흔들리지 않는다).
/// `.task(id:)` 라서 배율이 바뀌면 새 그림을 받고 화면에서 사라지면 요청이 취소된다.
struct PageImageView: View {
    let model: ViewerModel
    let page: Int
    /// 비트맵 배율(px→비트맵). 배율이 곧 작업 키이므로 바뀌면 다시 받는다.
    let scale: Double
    let size: CGSize

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.white)
            if let image {
                // 프레임에 맞춰 늘이므로 Image 의 scale 값은 크기에 영향이 없다.
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: RenderKey(page: page, scale: scale)) {
            image = await model.image(page: page, scale: scale)
        }
        .accessibilityElement()
        .accessibilityLabel("\(page + 1)쪽")
    }
}

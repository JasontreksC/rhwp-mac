import CoreGraphics
import RhwpViewer
import SwiftUI

/// 쪽 썸네일 목록. 시스템 사이드바 `List` 로 보여 주므로 선택 강조와 배경 질감은 시스템이 맡는다.
struct ThumbnailSidebar: View {
    let model: ViewerModel
    @Binding var visiblePage: Int?

    /// 썸네일의 화면 너비(pt).
    private let thumbnailWidth: Double = 132

    var body: some View {
        List(selection: $visiblePage) {
            ForEach(0..<model.pageCount, id: \.self) { page in
                ThumbnailRow(model: model, page: page, width: thumbnailWidth)
                    .tag(page)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ThumbnailRow: View {
    let model: ViewerModel
    let page: Int
    let width: Double

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        let size = model.pageSizes[page]
        let height = width * size.height / max(size.width, 1)
        VStack(spacing: 4) {
            ZStack {
                Rectangle().fill(.white)
                if let image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                }
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Text("\(page + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .task(id: displayScale) {
            let scale = model.thumbnailScale(page: page, width: width, displayScale: displayScale)
            image = await model.image(page: page, scale: scale)
        }
        .accessibilityLabel("\(page + 1)쪽 썸네일")
    }
}

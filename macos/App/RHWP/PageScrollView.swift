import RhwpViewer
import SwiftUI

/// 쪽을 세로로 쌓아 보여 주는 스크롤 영역.
///
/// `LazyVStack`이 화면에 가까운 쪽만 만들고, 쪽 크기는 `PageLayout`이 미리 정한다. 위로 보이는 쪽은
/// `scrollPosition(id:)` 로 `visiblePage`와 양방향으로 묶여 있어, 사이드바에서 쪽을 고르면 스크롤하고 스크롤하면
/// 사이드바의 선택이 따라온다. 확대 배율은 위쪽 도구 막대와 메뉴, 그리고 트랙패드 핀치로 바꾼다.
struct PageScrollView: View {
    let model: ViewerModel
    @Binding var visiblePage: Int?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let layout = model.layout
        GeometryReader { viewport in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(spacing: layout.spacing) {
                    ForEach(0..<layout.pageCount, id: \.self) { page in
                        let frame = layout.frames[page]
                        PageImageView(
                            model: model,
                            page: page,
                            scale: model.renderScale(page: page, displayScale: displayScale),
                            size: CGSize(width: frame.width, height: frame.height)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                        .id(page)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, layout.margin)
                .padding(.horizontal, layout.margin)
                // 내용이 창보다 좁으면 가운데에 두고, 넓으면 가로로 스크롤한다.
                .frame(minWidth: viewport.size.width, alignment: .center)
            }
            .scrollPosition(id: $visiblePage, anchor: .top)
            .background(.background.secondary)
            .onChange(of: viewport.size.width, initial: true) { _, width in
                model.viewportWidthChanged(width)
            }
        }
        // 트랙패드 핀치 확대·축소. 손을 뗄 때 가장 가까운 배율로 정한다(제스처 중 실시간 확대는 4단계의 몫).
        .gesture(
            MagnifyGesture().onEnded { value in
                model.setZoom(Zoom(model.zoom.factor * value.magnification))
            }
        )
    }
}

import RhwpViewer
import SwiftUI

/// 쪽을 세로로 쌓아 보여 주는 스크롤 영역.
///
/// `LazyVStack`이 화면에 가까운 쪽만 만들고, 쪽 크기는 `PageLayout`이 미리 정한다. 스크롤 지오메트리(보이는 영역)는 모델에
/// 알려서 어느 타일을 그릴지 정하게 하고, 모델이 요청하는 스크롤(확대할 때 붙잡은 곳을 유지하려는 것)을 따른다. 위로 보이는
/// 쪽은 `visiblePage`와 양방향으로 묶여 있어, 사이드바에서 쪽을 고르면 스크롤하고 스크롤하면 사이드바의 선택이 따라온다.
/// 확대 배율은 위쪽 도구 막대와 메뉴, 그리고 트랙패드 핀치로 바꾼다.
///
/// **핀치**: 제스처 중에는 배율·배치·타일을 바꾸지 않고, 지금 화면에 그려진 것을 `scaleEffect`로 즉시 늘여 보여 준다
/// (이미 그려진 타일을 늘이는 것이라 흐리다). 손을 떼면 모델이 새 배율을 정하고 그 배율의 타일을 채우는 동안 이전 타일이
/// 밑에 깔려 있어 흰 화면이 보이지 않는다.
struct PageScrollView: View {
    let model: ViewerModel
    @Binding var visiblePage: Int?

    @State private var position = ScrollPosition()

    var body: some View {
        let layout = model.layout
        let pinch = model.pinch
        GeometryReader { container in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(spacing: layout.spacing) {
                    ForEach(0..<layout.pageCount, id: \.self) { page in
                        let frame = layout.frames[page]
                        PageTilesView(model: model, page: page, size: CGSize(width: frame.width, height: frame.height))
                            .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                    }
                }
                .padding(.vertical, layout.margin)
                .padding(.horizontal, layout.margin)
                // 내용이 창보다 좁으면 가운데에 두고, 넓으면 가로로 스크롤한다.
                .frame(minWidth: container.size.width, alignment: .center)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: Viewport.self) { geometry in
                // contentOffset 은 인셋만큼 음수에서 시작한다(도구 막대·사이드바 아래까지 이어지는 상세 화면). 가려지지 않은
                // 영역의 왼쪽 위로 바꿔 넘긴다.
                let insets = geometry.contentInsets
                return Viewport(
                    offset: CGPoint(x: geometry.contentOffset.x + insets.leading, y: geometry.contentOffset.y + insets.top),
                    size: geometry.containerSize,
                    insets: ViewportInsets(leading: insets.leading, top: insets.top, trailing: insets.trailing, bottom: insets.bottom)
                )
            } action: { _, viewport in
                model.viewportChanged(viewport)
                // 위에 걸린 쪽을 사이드바에 알린다. 같은 값이면 대입하지 않아 불필요한 갱신과 되먹임을 막는다.
                let top = model.layout.topVisiblePage(offsetY: viewport.offset.y)
                if top != visiblePage { visiblePage = top }
            }
            .scaleEffect(
                pinch?.magnification ?? 1,
                anchor: UnitPoint(
                    x: (pinch?.anchor.x ?? 0) / max(container.size.width, 1),
                    y: (pinch?.anchor.y ?? 0) / max(container.size.height, 1)
                )
            )
        }
        // 확대한 내용이 스크롤 영역 밖(도구 막대·사이드바 쪽)으로 번지지 않게 자른다. 배경은 늘이지 않는다.
        .clipped()
        .background(.background.secondary)
        .gesture(
            MagnifyGesture()
                .onChanged { value in model.pinchChanged(magnification: value.magnification, anchor: value.startLocation) }
                .onEnded { _ in model.pinchEnded() }
        )
        // 모델의 스크롤 요청(확대 앵커)을 따른다.
        .onChange(of: model.scrollRequest) { _, request in
            guard let request else { return }
            position.scrollTo(x: request.offset.x, y: request.offset.y)
        }
        // 사이드바에서 다른 쪽을 골랐으면 그 쪽의 위로 스크롤한다. 스크롤해서 바뀐 값(이미 위에 걸린 쪽)이면 아무것도 하지 않는다.
        .onChange(of: visiblePage) { _, page in
            guard let page, page != model.layout.topVisiblePage(offsetY: model.viewport.offset.y),
                  let offset = model.layout.scrollOffset(forPage: page)
            else { return }
            // 가로 위치는 지금 보이는 곳을 그대로 둔다(`scrollTo(y:)`만 부르면 마지막 요청의 가로 위치로 되돌아간다).
            position.scrollTo(x: model.viewport.offset.x, y: offset)
        }
    }
}

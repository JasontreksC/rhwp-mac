import RhwpViewer
import SwiftUI

/// 문서 창 하나의 화면: 쪽 썸네일 사이드바와 쪽 스크롤 영역, 도구 막대.
///
/// 구성 요소는 시스템 컴포넌트뿐이다(`NavigationSplitView`, 사이드바 `List`, `ScrollView`, 도구 막대의 `Button`·
/// `Menu`). 맥 26의 Liquid Glass 도구 막대와 사이드바는 이들을 최신 SDK로 빌드하면 시스템이 입힌다.
struct DocumentView: View {
    let fileData: Data
    let fileName: String?

    @State private var model = ViewerModel()
    /// 화면 위에 보이는 쪽(0부터). 사이드바 선택과 스크롤 위치가 이 값을 함께 쓴다.
    @State private var visiblePage: Int? = 0

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("문서를 여는 중…")
            case let .failed(message):
                ContentUnavailableView(
                    "문서를 열 수 없습니다",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .ready where model.pageCount == 0:
                ContentUnavailableView("쪽이 없는 문서입니다", systemImage: "doc")
            case .ready:
                NavigationSplitView {
                    ThumbnailSidebar(model: model, visiblePage: $visiblePage)
                        .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 240)
                } detail: {
                    PageScrollView(model: model, visiblePage: $visiblePage)
                }
                .toolbar { viewerToolbar }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .focusedSceneValue(model)
        .task { await model.open(data: fileData) }
    }

    @ToolbarContentBuilder
    private var viewerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("축소", systemImage: "minus.magnifyingglass", action: model.zoomOut)
                .disabled(!model.zoom.canZoomOut)
                .help("축소 (⌘−)")
            Menu(model.zoom.percentLabel) {
                ForEach(Zoom.steps, id: \.self) { step in
                    Button("\(Zoom(step).percentLabel)") { model.setZoom(Zoom(step), anchor: model.viewportCenter) }
                }
                Divider()
                Button("실제 크기", action: model.actualSize)
                Button("너비에 맞춤", action: model.fitWidth)
            }
            .help("확대 배율")
            Button("확대", systemImage: "plus.magnifyingglass", action: model.zoomIn)
                .disabled(!model.zoom.canZoomIn)
                .help("확대 (⌘+)")
        }
        ToolbarItem(placement: .status) {
            Text("\((visiblePage ?? 0) + 1) / \(model.pageCount)쪽")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

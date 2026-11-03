import RhwpViewer
import SwiftUI

/// 보기 메뉴의 확대·축소 명령. 앞에 있는 문서 창의 `ViewerModel`에 작용한다.
///
/// 맥의 메뉴는 창마다 다른 모델을 가리켜야 하므로 `focusedSceneValue`로 현재 창의 모델을 받는다.
struct ViewerCommands: Commands {
    @FocusedValue(ViewerModel.self) private var model

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("확대") { model?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(model?.zoom.canZoomIn != true)
            Button("축소") { model?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model?.zoom.canZoomOut != true)
            Button("실제 크기") { model?.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(model == nil)
            Button("너비에 맞춤") { model?.fitWidth() }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(model == nil)
        }
    }
}

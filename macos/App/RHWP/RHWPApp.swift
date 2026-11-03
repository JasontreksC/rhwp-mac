import SwiftUI

/// RHWP 앱의 진입점.
///
/// 문서 앱이므로 `DocumentGroup` 이 열기·창·최근 문서·전체 화면 같은 맥의 문서 동작을 시스템 방식 그대로
/// 맡는다. 3단계는 읽기 전용 뷰어라 `viewing:` 이고, 편집이 들어오는 6단계에서 편집 가능한 그룹으로 바꾼다.
@main
struct RHWPApp: App {
    var body: some Scene {
        DocumentGroup(viewing: HwpFileDocument.self) { file in
            DocumentView(fileData: file.document.data, fileName: file.fileURL?.lastPathComponent)
        }
        .commands {
            ViewerCommands()
        }
    }
}

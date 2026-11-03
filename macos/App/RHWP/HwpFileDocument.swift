import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    // Info.plist(project.yml)의 UTExportedTypeDeclarations 와 같은 식별자다.
    static let hwp = UTType(exportedAs: "io.github.jasontreksc.rhwp.hwp")
    static let hwpx = UTType(exportedAs: "io.github.jasontreksc.rhwp.hwpx")
    static let hml = UTType(exportedAs: "io.github.jasontreksc.rhwp.hml")
}

/// 열린 HWP/HWPX/HML 파일의 내용.
///
/// 파일 읽기는 시스템(DocumentGroup)이 샌드박스·파일 코디네이션에 맞게 하고, 바이트는 엔진에 그대로 넘긴다.
/// 파싱은 `RhwpDocumentSession` 이 문서 전용 큐에서 하므로 여기서는 하지 않는다.
struct HwpFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.hwp, .hwpx, .hml]
    /// 3단계는 읽기 전용이다. 저장은 9단계에서 연다.
    static let writableContentTypes: [UTType] = []

    let data: Data

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}

import CRhwp
import Foundation

// FFI 왕복 스모크: XCFramework 를 Swift 로 링크해 핸들 API 의 소유권·오류 규칙을 실제로 실행한다.
// Rust 단위 테스트가 Rust 쪽 계약을 검증한다면, 이 파일은 헤더·모듈맵·링크·Swift 호출 규약을 검증한다.
// 실패하면 종료 코드 1 이다.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("스모크 실패: \(message)\n".utf8))
    exit(1)
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

/// Rust 가 돌려준 문자열을 Swift 로 옮기고 Rust 쪽 할당을 해제한다. (소유권은 항상 호출자에게 있다.)
func takeString(_ raw: UnsafeMutablePointer<CChar>?) -> String {
    guard let raw else { fail("Rust 가 null 문자열을 돌려줌") }
    defer { rhwp_string_free(raw) }
    return String(cString: raw)
}

func parseObject(_ json: String) -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
        fail("JSON 객체가 아님: \(json.prefix(120))")
    }
    return object
}

guard CommandLine.arguments.count == 2 else { fail("사용법: ffi_smoke <KTX.hwp 경로>") }
let samplePath = CommandLine.arguments[1]

// 1) 경로로 열기 → 쪽수 → 레이어 트리 → 해제
var openError: UnsafeMutablePointer<CChar>?
guard let document = rhwp_document_open(samplePath, &openError) else {
    fail("문서 열기 실패: \(takeString(openError))")
}
check(openError == nil, "성공했는데 out_error 가 비어 있지 않음")
// KTX.hwp 는 한컴 PDF(pdf/KTX-2022.pdf)가 27쪽이다.
check(rhwp_document_page_count(document) == 27, "쪽수가 27이 아님")

let tree = parseObject(takeString(rhwp_document_page_layer_tree(document, 0)))
check(tree["ok"] as? Bool == true, "레이어 트리 ok != true")
check(tree["pageCount"] as? Int == 27, "봉투 pageCount != 27")
let layerTree = tree["layerTree"] as? [String: Any]
check((layerTree?["pageWidth"] as? Double ?? 0) > 0, "layerTree.pageWidth 없음")
check(layerTree?["root"] is [String: Any], "layerTree.root 없음")

// 2) 범위 밖 쪽은 오류 봉투(예외나 크래시가 아니다)
let outOfRange = parseObject(takeString(rhwp_document_page_layer_tree(document, 27)))
check(outOfRange["ok"] as? Bool == false, "범위 밖 쪽이 ok 로 돌아옴")
rhwp_document_free(document)

// 3) 메모리 바이트로 열기. 호출이 끝난 뒤 버퍼를 버려도 되는지(복사)도 함께 확인한다.
// (불투명 구조체 `RhwpDocument *` 는 Swift 에서 `OpaquePointer` 로 들어온다.)
guard var bytes = FileManager.default.contents(atPath: samplePath).map({ [UInt8]($0) }) else {
    fail("샘플을 읽을 수 없음")
}
var bytesError: UnsafeMutablePointer<CChar>?
let bytesDocument = bytes.withUnsafeBufferPointer {
    rhwp_document_open_bytes($0.baseAddress, $0.count, &bytesError)
}
guard let bytesDocument else { fail("바이트로 열기 실패: \(takeString(bytesError))") }
bytes.removeAll(keepingCapacity: false)   // 호출 뒤 원본 버퍼는 없어도 된다.
check(rhwp_document_page_count(bytesDocument) == 27, "바이트로 연 문서의 쪽수가 27이 아님")
rhwp_document_free(bytesDocument)

// 4) 열기 실패는 널 핸들 + 오류 JSON
var missingError: UnsafeMutablePointer<CChar>?
check(rhwp_document_open("/nonexistent/rhwp.hwp", &missingError) == nil, "없는 파일이 열림")
check(parseObject(takeString(missingError))["ok"] as? Bool == false, "오류 JSON 의 ok != false")

// 5) 널은 안전하게 거부·무시된다
check(rhwp_document_page_count(nil) == -1, "널 핸들의 쪽수가 -1 이 아님")
rhwp_document_free(nil)
rhwp_string_free(nil)

print("FFI 왕복 스모크 통과")

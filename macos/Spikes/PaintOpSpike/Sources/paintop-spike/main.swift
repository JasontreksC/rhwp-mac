import CRhwp
import Foundation

// 0단계 스파이크 진입점.
//   paintop-spike <문서> <쪽(0부터)> <출력.png | 출력.json>
// 출력이 .json 이면 Rust가 돌려준 레이어 트리 원문만 저장하고(형식 확인용),
// .png 이면 CoreGraphics/CoreText로 재생한 결과를 저장한다.

/// Rust FFI로 문서를 열어 한 쪽의 레이어 트리 JSON 원문을 받아 온다.
/// 핸들 기반 API(1단계)를 쓰므로 문서는 열린 동안 한 번만 파싱된다.
/// 반환 문자열은 Rust 할당자 소유이므로 반드시 `rhwp_string_free`로 해제한다.
func fetchLayerTreeJSON(path: String, page: Int32) throws -> Data {
    guard page >= 0 else { throw SpikeError.usage }

    var openError: UnsafeMutablePointer<CChar>?
    guard let document = rhwp_document_open(path, &openError) else {
        throw SpikeError.nativeError(takeString(openError))
    }
    defer { rhwp_document_free(document) }

    guard let raw = rhwp_document_page_layer_tree(document, UInt32(page)) else {
        throw SpikeError.nullResult
    }
    // Swift 쪽으로 복사한 뒤에 해제한다. 해제 후의 포인터는 읽으면 안 된다.
    defer { rhwp_string_free(raw) }
    return Data(bytes: raw, count: strlen(raw))
}

/// Rust가 돌려준 문자열을 Swift로 옮기고 Rust 쪽 할당을 해제한다.
func takeString(_ raw: UnsafeMutablePointer<CChar>?) -> String {
    guard let raw else { return "(null)" }
    defer { rhwp_string_free(raw) }
    return String(cString: raw)
}

enum SpikeError: Error, CustomStringConvertible {
    case usage
    case nullResult
    case nativeError(String)
    case malformed(String)

    var description: String {
        switch self {
        case .usage: return "사용법: paintop-spike <문서> <쪽(0부터)> <출력.png|출력.json>"
        case .nullResult: return "Rust FFI가 null을 돌려줌"
        case let .nativeError(message): return "Rust 오류: \(message)"
        case let .malformed(message): return "레이어 트리 형식 오류: \(message)"
        }
    }
}

func run() throws {
    let args = CommandLine.arguments
    guard args.count == 4, let page = Int32(args[2]) else { throw SpikeError.usage }
    let json = try fetchLayerTreeJSON(path: args[1], page: page)
    let output = URL(fileURLWithPath: args[3])

    if output.pathExtension == "json" {
        try json.write(to: output)
        print("레이어 트리 JSON \(json.count)바이트 저장: \(output.path)")
        return
    }

    // Rust 응답 봉투를 벗기고 layerTree만 꺼낸다.
    guard let envelope = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
        throw SpikeError.malformed("최상위가 객체가 아님")
    }
    if envelope["ok"] as? Bool != true {
        throw SpikeError.nativeError(envelope["error"] as? String ?? "알 수 없음")
    }
    guard let layerTree = envelope["layerTree"] as? [String: Any] else {
        throw SpikeError.malformed("layerTree 누락")
    }

    let renderer = PageRenderer()
    let started = ContinuousClock.now
    let image = try renderer.render(layerTree: layerTree, scale: 2)
    let elapsed = ContinuousClock.now - started
    try writePNG(image, to: output)

    // 커버리지 보고: 무엇을 그렸고 무엇을 건너뛰었는지.
    print("PNG 저장: \(output.path) (\(image.width)x\(image.height), 재생 \(elapsed))")
    print("그린 op:", renderer.rendered.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    print("건너뛴 op:", renderer.skipped.isEmpty ? "없음"
          : renderer.skipped.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    for (requested, used) in renderer.fontSubstitutions.sorted(by: { $0.key < $1.key }) {
        print("글꼴 대체: \(requested) → \(used)")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

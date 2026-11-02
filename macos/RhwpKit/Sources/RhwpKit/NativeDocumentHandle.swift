import CRhwp
import Foundation

/// 네이티브 문서 핸들(`RhwpDocument *`)의 소유자.
///
/// 핸들의 수명을 Swift 참조 수명에 묶는다: 마지막 참조가 사라지면 `deinit`이 `rhwp_document_free`를 부른다.
/// 이 클래스 자체는 호출을 직렬화하지 않는다. 문서 접근은 `RhwpDocumentSession` actor가 전용 큐 위에서
/// 직렬화하며, 그래서 `@unchecked Sendable`이다(소유권 이전과 해제만 스레드 사이를 오간다).
final class NativeDocumentHandle: @unchecked Sendable {
    private let pointer: OpaquePointer

    private init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        rhwp_document_free(pointer)
    }

    /// 메모리의 파일 내용으로 문서를 연다. 네이티브가 바이트를 호출 안에서 복사하므로 `data`는 호출 뒤 버려도 된다.
    static func open(data: Data) throws -> NativeDocumentHandle {
        var error: UnsafeMutablePointer<CChar>?
        let handle = data.withUnsafeBytes { buffer -> OpaquePointer? in
            let base = buffer.bindMemory(to: UInt8.self).baseAddress
            return rhwp_document_open_bytes(base, buffer.count, &error)
        }
        guard let handle else {
            throw RhwpError.openFailed(errorMessage(takingOwnershipOf: error))
        }
        return NativeDocumentHandle(pointer: handle)
    }

    /// 전체 쪽수. 문서를 더 쓸 수 없으면 `documentUnavailable`.
    func pageCount() throws -> Int {
        let count = rhwp_document_page_count(pointer)
        guard count >= 0 else { throw RhwpError.documentUnavailable }
        return Int(count)
    }

    /// 한 쪽의 레이어 트리 응답 원문(JSON 봉투). 범위 검사는 호출자가 이미 했다고 가정한다.
    func pageLayerTreeJSON(page: UInt32) throws -> Data {
        guard let raw = rhwp_document_page_layer_tree(pointer, page) else {
            throw RhwpError.malformedResponse("네이티브가 null 문자열을 돌려줌")
        }
        // 복사한 뒤에 해제한다. 해제한 포인터는 읽으면 안 된다.
        defer { rhwp_string_free(raw) }
        return Data(bytes: raw, count: strlen(raw))
    }

    /// `out_error`로 받은 오류 문자열을 읽고 해제해, 사람이 읽을 메시지를 돌려준다.
    private static func errorMessage(takingOwnershipOf raw: UnsafeMutablePointer<CChar>?) -> String {
        guard let raw else { return "알 수 없는 오류(오류 메시지 없음)" }
        defer { rhwp_string_free(raw) }
        let text = String(cString: raw)
        // {"ok":false,"error":"..."} 에서 error 만 꺼낸다. 형식이 다르면 원문을 그대로 쓴다.
        struct ErrorEnvelope: Decodable { let error: String? }
        let message = try? JSONDecoder().decode(ErrorEnvelope.self, from: Data(text.utf8)).error
        return message ?? text
    }
}

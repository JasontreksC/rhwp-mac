import Foundation

/// 네이티브 응답 봉투 `{"ok":true,"pageCount":N,"page":P,"layerTree":{...}}` /
/// `{"ok":false,"error":"..."}` 의 디코딩.
enum NativeEnvelope {
    private struct Response: Decodable {
        let ok: Bool
        let error: String?
        let layerTree: PageLayerTree?
    }

    static func decodeLayerTree(from json: Data) throws -> PageLayerTree {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: json)
        } catch {
            throw RhwpError.malformedResponse(describe(error))
        }
        guard response.ok else {
            throw RhwpError.native(response.error ?? "알 수 없는 오류(오류 메시지 없음)")
        }
        guard let tree = response.layerTree else {
            throw RhwpError.malformedResponse("ok 응답에 layerTree가 없음")
        }
        return tree
    }

    /// 디코딩 오류를 어느 필드에서 났는지 알 수 있는 한 줄로 만든다.
    private static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return String(describing: error) }
        let context: DecodingError.Context
        switch decodingError {
        case let .typeMismatch(_, ctx), let .valueNotFound(_, ctx), let .keyNotFound(_, ctx), let .dataCorrupted(ctx):
            context = ctx
        @unknown default:
            return String(describing: decodingError)
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return "\(path): \(context.debugDescription)"
    }
}

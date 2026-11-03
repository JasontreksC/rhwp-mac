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

    private struct PageSizesResponse: Decodable {
        let ok: Bool
        let error: String?
        let pageCount: Int?
        let pages: [PageSize]?
    }

    /// `{"ok":true,"pageCount":N,"pages":[{"width":W,"height":H},...]}` 를 읽는다.
    /// `pages` 의 개수가 `pageCount` 와 다르면 스키마 위반으로 보고 실패시킨다(자리를 잘못 잡느니 멈춘다).
    static func decodePageSizes(from json: Data) throws -> [PageSize] {
        let response: PageSizesResponse
        do {
            response = try JSONDecoder().decode(PageSizesResponse.self, from: json)
        } catch {
            throw RhwpError.malformedResponse(describe(error))
        }
        guard response.ok else {
            throw RhwpError.native(response.error ?? "알 수 없는 오류(오류 메시지 없음)")
        }
        guard let pages = response.pages, let pageCount = response.pageCount, pages.count == pageCount else {
            throw RhwpError.malformedResponse("pages 개수가 pageCount와 다르거나 없음")
        }
        return pages
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

extension PageLayerTree {
    /// 엔진 응답 봉투(`layerTreeJSON(page:)`가 돌려주는 원문)에서 레이어 트리를 읽는다.
    /// 원문을 따로 저장해 두었다가(진단·골든 비교) 같은 해석을 다시 적용할 때 쓴다.
    public static func decode(envelope json: Data) throws -> PageLayerTree {
        try NativeEnvelope.decodeLayerTree(from: json)
    }
}

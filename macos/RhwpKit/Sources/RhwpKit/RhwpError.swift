import Foundation

/// RhwpKit이 던지는 오류.
///
/// 네이티브 계층의 오류는 `{"ok":false,"error":"..."}` JSON 봉투로 온다. 그 메시지는 사람이 읽는 문장이라
/// 문자열로 분기하지 않는다. 호출자가 구분해야 하는 경우(범위 밖 쪽, 사용할 수 없는 문서)는 Swift 쪽에서
/// 먼저 검사해 전용 케이스로 돌려주고, 나머지는 `.native`로 메시지를 그대로 전달한다.
public enum RhwpError: Error, Sendable, Equatable {
    /// 문서를 열지 못했다(파일 읽기 실패, 지원하지 않는 형식, 손상된 파일, 암호 문서 등).
    case openFailed(String)
    /// 요청한 쪽이 문서의 쪽 범위(`0..<pageCount`)를 벗어났다.
    case pageOutOfRange(page: Int, pageCount: Int)
    /// 이전 호출에서 네이티브 계층이 panic을 일으켜 이 문서를 더 쓸 수 없다. 문서를 다시 열어야 한다.
    case documentUnavailable
    /// 네이티브 계층이 오류 봉투를 돌려줬다.
    case native(String)
    /// 네이티브 응답이 약속된 JSON 형식이 아니다(스키마 변경 또는 버그).
    case malformedResponse(String)
}

extension RhwpError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "문서를 열 수 없습니다: \(message)"
        case let .pageOutOfRange(page, pageCount):
            return "쪽 번호가 범위를 벗어났습니다: \(page) (전체 \(pageCount)쪽)"
        case .documentUnavailable:
            return "문서 상태를 신뢰할 수 없어 더 이상 사용할 수 없습니다. 문서를 다시 여십시오."
        case let .native(message):
            return message
        case let .malformedResponse(detail):
            return "엔진 응답을 해석할 수 없습니다: \(detail)"
        }
    }
}

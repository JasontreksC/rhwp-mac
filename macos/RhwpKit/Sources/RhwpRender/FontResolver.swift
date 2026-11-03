import CoreText
import Foundation

/// 문서가 지정한 글꼴 이름을 이 맥에서 쓸 수 있는 글꼴로 해석한다.
///
/// 한컴 글꼴(HY헤드라인M, 한컴바탕 등)은 맥에 없다. 설치되지 않은 글꼴은 명조·바탕 계열이면 AppleMyungjo,
/// 그 밖에는 Apple SD Gothic Neo로 대체한다. 이 대체가 렌더 충실도를 가장 크게 깎는 요인이므로 대체 사실을
/// 숨기지 않고 `ResolvedFont.substitute`로 돌려준다(글꼴 공급 방침은 4단계에서 정한다).
///
/// 여러 렌더가 같은 해석기를 공유하므로 캐시는 잠금으로 보호한다. `CTFont`는 불변이라 읽기는 안전하다.
public final class FontResolver: @unchecked Sendable {
    public struct ResolvedFont: @unchecked Sendable {
        public let font: CTFont
        /// 문서의 글꼴 이름과 다른 글꼴로 대체했다면 실제로 쓴 글꼴 가족 이름. 대체하지 않았으면 nil.
        public let substitute: String?
    }

    private let lock = NSLock()
    private var cache: [String: ResolvedFont] = [:]

    public init() {}

    public func resolve(family: String, size: Double, bold: Bool, italic: Bool) -> ResolvedFont {
        let key = "\(family)|\(size)|\(bold)|\(italic)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }

        var font = CTFontCreateWithName(family as CFString, size, nil)
        var substitute: String?
        let actualFamily = CTFontCopyFamilyName(font) as String
        if actualFamily.caseInsensitiveCompare(family) != .orderedSame {
            let serif = ["명조", "바탕", "myungjo", "batang", "serif"].contains { family.lowercased().contains($0) }
            font = CTFontCreateWithName((serif ? "AppleMyungjo" : "Apple SD Gothic Neo") as CFString, size, nil)
            substitute = CTFontCopyFamilyName(font) as String
        }

        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) {
            font = styled
        }
        let resolved = ResolvedFont(font: font, substitute: substitute)
        cache[key] = resolved
        return resolved
    }
}

import CoreText
import Foundation

/// 문서가 지정한 글꼴 이름을 이 맥에서 쓸 수 있는 글꼴로 해석한다.
///
/// 한컴 글꼴(HY헤드라인M, 함초롬바탕 등)은 맥에 없고 이 앱은 그 글꼴을 번들하지 않는다(라이선스). 대신
/// **글꼴 이름 → 후보 목록** 표(`FontSubstitution`)로 같은 성격의 시스템 글꼴을 고른다. 설치된 첫 후보를 쓰고,
/// 하나도 없으면 모든 macOS에 있는 Apple SD Gothic Neo로 떨어진다. 대체 사실은 숨기지 않고
/// `ResolvedFont.substitute`로 돌려주며 `RenderReport.fontSubstitutions`에 모인다.
///
/// 글꼴 이름은 CSS `font-family` 같은 **쉼표 목록**(`'Latin Modern Math', 'STIX Two Text', serif`)도 받는다.
/// 엔진이 수식·차트 SVG에 이런 목록을 싣는다. 목록에서 설치된 첫 글꼴을 쓰고, 하나도 없으면 목록의 첫 이름으로
/// 표를 찾는다.
///
/// 여러 렌더가 같은 해석기를 공유하므로 캐시는 잠금으로 보호한다. `CTFont`는 불변이라 읽기는 안전하다.
public final class FontResolver: @unchecked Sendable {
    public struct ResolvedFont: @unchecked Sendable {
        public let font: CTFont
        /// 문서가 요청한 글꼴(목록이면 첫 항목).
        public let requested: String
        /// 문서의 글꼴 이름과 다른 글꼴로 대체했다면 실제로 쓴 글꼴 가족 이름. 대체하지 않았으면 nil.
        public let substitute: String?
    }

    private let lock = NSLock()
    private var cache: [String: ResolvedFont] = [:]

    public init() {}

    public func resolve(family: String, size: Double, bold: Bool, italic: Bool) -> ResolvedFont {
        resolve(familyList: family, size: size, bold: bold, italic: italic)
    }

    public func resolve(familyList: String, size: Double, bold: Bool, italic: Bool) -> ResolvedFont {
        let key = "\(familyList)|\(size)|\(bold)|\(italic)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }

        let candidates = Self.candidates(in: familyList)
        let requested = candidates.first ?? familyList
        var font: CTFont?
        for name in candidates {
            if let installed = Self.installedFont(named: name, size: size) {
                font = installed
                break
            }
        }
        var substitute: String?
        if font == nil {
            // 목록의 이름이 하나도 설치돼 있지 않다. 첫 이름(없으면 목록 전체)으로 대체 표를 찾는다.
            for name in FontSubstitution.candidates(for: requested) {
                if let installed = Self.installedFont(named: name, size: size) {
                    font = installed
                    break
                }
            }
            let fallback = font ?? CTFontCreateWithName(FontSubstitution.lastResort as CFString, size, nil)
            font = fallback
            substitute = CTFontCopyFamilyName(fallback) as String
        } else if let found = font, let first = candidates.first,
                  (CTFontCopyFamilyName(found) as String).caseInsensitiveCompare(first) != .orderedSame {
            // 목록의 뒤쪽 항목으로 내려갔다면 요청한 글꼴과 다른 글꼴을 쓴 것이다.
            substitute = CTFontCopyFamilyName(found) as String
        }

        var resolvedFont = font!
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(resolvedFont, size, nil, traits, traits) {
            resolvedFont = styled
        }
        let resolved = ResolvedFont(font: resolvedFont, requested: requested, substitute: substitute)
        cache[key] = resolved
        return resolved
    }

    /// `'A', "B C", serif`를 `["A", "B C", "serif"]`로 나눈다.
    static func candidates(in list: String) -> [String] {
        list.split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t'\""))
        }.filter { !$0.isEmpty }
    }

    /// 이름이 실제로 설치된 글꼴 가족이면 그 글꼴을 돌려준다. `CTFontCreateWithName`은 없는 이름에도 기본 글꼴을
    /// 돌려주므로 가족 이름이 일치하는지로 판정한다. CSS 일반 가족(`serif`, `sans-serif`)은 설치된 글꼴이 아니다.
    private static func installedFont(named name: String, size: Double) -> CTFont? {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let family = CTFontCopyFamilyName(font) as String
        return family.caseInsensitiveCompare(name) == .orderedSame ? font : nil
    }
}

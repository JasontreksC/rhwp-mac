import Foundation

/// 설치되지 않은 글꼴 이름을 같은 성격의 macOS 글꼴 후보로 옮기는 표.
///
/// 규칙은 두 겹이다. ① 이름이 표에 있으면 그 후보 목록(정확히 한 글꼴을 겨냥), ② 없으면 이름의 성격(명조·고딕·
/// 궁서·헤드라인·고정폭)으로 분류해 그 계열의 후보 목록. 어느 쪽이든 목록을 앞에서부터 보며 설치된 첫 글꼴을
/// 쓴다. 이 맥에 없는 후보는 건너뛰므로 목록은 "있으면 더 좋은 순서"로 쓴다.
///
/// 후보의 순서는 한컴 PDF와의 실루엣 일치율(`macos/scripts/fidelity-sweep.py`)로 골랐다. 결과와 근거는
/// `mydocs/tech/macos_native_app_architecture.md`의 4단계 절에 있다.
enum FontSubstitution {
    /// 어떤 후보도 없을 때. 한글을 가진 글꼴 중 모든 macOS에 있는 것이다.
    static let lastResort = "Apple SD Gothic Neo"

    static let serif = ["Nanum Myeongjo", "AppleMyungjo", "PCMyungjo", "Times New Roman"]
    static let sans = ["Apple SD Gothic Neo", "Nanum Gothic", "AppleGothic", "Helvetica Neue"]
    private static let monospaced = ["Menlo", "AppleGothic", "Courier New"]
    private static let gungseo = ["GungSeo", "AppleMyungjo"]
    private static let headline = ["HeadLineA", "Apple SD Gothic Neo"]

    /// 이름 하나에 대한 후보 목록(앞이 우선). 이름은 대소문자·공백·하이픈과 무관하게 찾는다.
    static func candidates(for name: String) -> [String] {
        let key = normalize(name)
        if let exact = exactTable[key] { return exact }
        // CSS 일반 가족.
        switch key {
        case "serif": return serif
        case "sansserif", "system-ui", "systemui": return sans
        case "monospace": return monospaced
        default: break
        }
        // 이름에 든 낱말로 계열을 짐작한다. 순서가 중요하다: "헤드라인"·"궁서"를 "명조"보다 먼저 본다.
        if contains(key, ["헤드라인", "headline"]) { return headline }
        if contains(key, ["궁서", "gungsuh", "gungseo"]) { return gungseo }
        if contains(key, ["명조", "바탕", "myeongjo", "myungjo", "batang", "serif", "mincho", "song", "ming"]) { return serif }
        if contains(key, ["mono", "courier", "consolas", "코딩"]) { return monospaced }
        return sans
    }

    /// 자주 쓰이는 이름의 정확한 대응. 키는 `normalize` 결과다.
    private static let exactTable: [String: [String]] = [
        // 라틴 글꼴: 같은 모양이 맥에 있으면 그것을 쓴다.
        "palatinolinotype": ["Palatino", "Book Antiqua"] + serif,
        "bookantiqua": ["Palatino"] + serif,
        "timesnewroman": ["Times New Roman", "Times"] + serif,
        "times": ["Times"] + serif,
        "georgia": ["Georgia"] + serif,
        "cambria": ["Cambria", "Times New Roman"] + serif,
        "arial": ["Arial", "Helvetica Neue"] + sans,
        "helvetica": ["Helvetica Neue", "Helvetica"] + sans,
        "calibri": ["Calibri", "Helvetica Neue"] + sans,
        "verdana": ["Verdana"] + sans,
        "tahoma": ["Tahoma"] + sans,
        "couriernew": ["Courier New", "Menlo"],
        // 수식 글꼴. 엔진이 수식 SVG의 글꼴 목록에 싣는다.
        "latinmodernmath": ["Latin Modern Math", "STIX Two Text", "STIXGeneral"] + serif,
        "stixtwotext": ["STIX Two Text", "STIXGeneral"] + serif,
        "stixtwomath": ["STIX Two Math", "STIX Two Text", "STIXGeneral"] + serif,
        // 한컴·한양 고딕 계열이지만 이름에 고딕이 없는 것들.
        "맑은고딕": sans,
        "굴림": sans,
        "돋움": sans,
        "함초롬돋움": sans,
        "한컴돋움": sans,
        "굴림체": ["AppleGothic"] + sans,
        "돋움체": ["AppleGothic"] + sans,
        "휴먼고딕": sans,
        "hy중고딕": sans,
        "hy견고딕": sans,
        "한양중고딕": sans,
        // 한컴 바탕 계열.
        "함초롬바탕": serif,
        "한컴바탕": serif,
        "haansoftbatang": serif,
    ]

    private static func normalize(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }

    private static func contains(_ key: String, _ words: [String]) -> Bool {
        words.contains { key.contains($0) }
    }
}

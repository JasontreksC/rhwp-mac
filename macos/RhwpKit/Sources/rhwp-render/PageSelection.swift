import Foundation

/// `1-8`, `3`, `1,3,5-7` 같은 쪽 목록(1부터)을 해석한다. `visual_sweep.py --pages`와 같은 표기다.
struct PageSelection {
    private let ranges: [ClosedRange<Int>]

    /// 잘못된 표기나 0 이하의 쪽 번호면 nil.
    init?(_ text: String) {
        var parsed: [ClosedRange<Int>] = []
        for part in text.split(separator: ",") {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
            switch bounds.count {
            case 1:
                guard let page = bounds[0], page >= 1 else { return nil }
                parsed.append(page...page)
            case 2:
                guard let low = bounds[0], let high = bounds[1], low >= 1, low <= high else { return nil }
                parsed.append(low...high)
            default:
                return nil
            }
        }
        guard !parsed.isEmpty else { return nil }
        ranges = parsed
    }

    func contains(_ page: Int) -> Bool {
        ranges.contains { $0.contains(page) }
    }
}

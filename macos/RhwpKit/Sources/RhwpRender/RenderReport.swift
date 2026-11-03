import CoreGraphics
import Foundation

/// 한 쪽을 그린 결과 집계. 무엇을 그렸고 무엇을 건너뛰었는지, 글꼴이 어떻게 대체됐는지를 드러낸다.
///
/// 렌더러가 조용히 빼먹은 것이 없도록, 레이어 트리의 모든 op는 `rendered`나 `skipped` 어느 한쪽에 반드시 들어간다.
/// (`rendered` 합 + `skipped`의 op 항목 합 = 트리의 op 수. 시험이 이 불변식을 지킨다.)
public struct RenderReport: Sendable, Equatable {
    /// 그린 항목의 종류별 개수. 키는 `op:<엔진 op 이름>` 형식이다.
    public internal(set) var rendered: [String: Int] = [:]
    /// 건너뛴 항목의 종류별 개수. 키는 `op:<이름>`, `node:<종류>`, `path:<명령>`, `gradient:type<N>` 형식이다.
    /// 근사해서 그린 항목은 `path:arcTo(approximated)`처럼 괄호로 표시하고, 이 경우 `rendered`에도 센다.
    public internal(set) var skipped: [String: Int] = [:]
    /// 문서가 지정한 글꼴 → 실제로 쓴 글꼴. 한컴 글꼴이 맥에 없을 때의 대체 현황이다.
    public internal(set) var fontSubstitutions: [String: String] = [:]

    public init() {}

    mutating func countRendered(_ key: String) { rendered[key, default: 0] += 1 }
    mutating func countSkipped(_ key: String) { skipped[key, default: 0] += 1 }

    /// 건너뛴 `op:` 항목의 합. 렌더링한 op 수와 합쳐 트리의 op 수와 맞는지 확인하는 데 쓴다.
    public var skippedOpCount: Int {
        skipped.filter { $0.key.hasPrefix("op:") }.values.reduce(0, +)
    }

    /// 그린 `op:` 항목의 합.
    public var renderedOpCount: Int {
        rendered.filter { $0.key.hasPrefix("op:") }.values.reduce(0, +)
    }
}

/// 렌더링 결과: 비트맵과 집계.
public struct RenderedPage: @unchecked Sendable {
    public let image: CGImage
    public let report: RenderReport
}

public enum RenderError: Error, Equatable {
    /// 쪽 크기가 비트맵으로 만들 수 없는 값(0 이하, 비정상적으로 큼)이다.
    case invalidPageSize(width: Double, height: Double)
    /// 비트맵 컨텍스트나 이미지를 만들지 못했다.
    case bitmapUnavailable
}

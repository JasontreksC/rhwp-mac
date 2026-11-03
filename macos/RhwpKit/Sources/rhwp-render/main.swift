import Foundation
import RhwpKit
import RhwpRender

// 문서의 한 쪽을 PNG로 그리거나 레이어 트리 JSON 원문을 저장하는 도구.
//
//   rhwp-render <문서> <쪽(0부터)> <출력.png | 출력.json> [--scale N]
//
// 출력이 .json 이면 엔진이 돌려준 응답 원문(봉투 포함)만 저장하고(형식 확인용), .png 이면 CoreGraphics로 그린
// 결과를 저장한다. 시각 검증(scripts/visual_sweep.py --png-pair)의 입력 PNG를 만드는 용도다.
// 0단계 스파이크(paintop-spike)를 대체한다.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let usage = "사용법: rhwp-render <문서> <쪽(0부터)> <출력.png|출력.json> [--scale N]"

var arguments = Array(CommandLine.arguments.dropFirst())
var scale = 2.0
if let flag = arguments.firstIndex(of: "--scale") {
    guard flag + 1 < arguments.count, let value = Double(arguments[flag + 1]), value > 0 else { fail(usage) }
    scale = value
    arguments.removeSubrange(flag...(flag + 1))
}
guard arguments.count == 3, let page = Int(arguments[1]), page >= 0 else { fail(usage) }
let documentURL = URL(fileURLWithPath: arguments[0])
let outputURL = URL(fileURLWithPath: arguments[2])

do {
    let session = try await RhwpDocumentSession.open(contentsOf: documentURL)

    if outputURL.pathExtension == "json" {
        let json = try await session.layerTreeJSON(page: page)
        try json.write(to: outputURL)
        print("레이어 트리 JSON \(json.count)바이트 저장: \(outputURL.path)")
    } else {
        let tree = try await session.layerTree(page: page)
        let started = ContinuousClock.now
        let rendered = try PageRenderer().render(tree, scale: scale)
        let elapsed = ContinuousClock.now - started
        guard let png = rendered.pngData() else { fail("PNG 인코딩 실패") }
        try png.write(to: outputURL)

        let report = rendered.report
        print("PNG 저장: \(outputURL.path) (\(rendered.image.width)x\(rendered.image.height), 재생 \(elapsed))")
        print("그린 op:", report.rendered.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        print("건너뛴 op:", report.skipped.isEmpty ? "없음"
              : report.skipped.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        for (requested, used) in report.fontSubstitutions.sorted(by: { $0.key < $1.key }) {
            print("글꼴 대체: \(requested) → \(used)")
        }
    }
} catch {
    fail("\(error.localizedDescription)")
}

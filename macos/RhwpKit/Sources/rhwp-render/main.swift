import Foundation
import RhwpKit
import RhwpRender

// 문서의 한 쪽을 PNG로 그리거나 레이어 트리 JSON 원문을 저장하는 도구.
//
//   rhwp-render <문서> <쪽(0부터)> <출력.png | 출력.json> [--scale N]
//   rhwp-render <문서> --all <출력폴더> [--pages 1-8] [--scale N]
//   rhwp-render --pdf <PDF> <출력폴더> [--pages 1-8] [--scale N]
//
// 출력이 .json 이면 엔진이 돌려준 응답 원문(봉투 포함)만 저장하고(형식 확인용), .png 이면 CoreGraphics로 그린
// 결과를 저장한다. 시각 검증(scripts/visual_sweep.py --png-pair)의 입력 PNG를 만드는 용도다.
// 0단계 스파이크(paintop-spike)를 대체한다.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let usage = """
사용법:
  rhwp-render <문서> <쪽(0부터)> <출력.png|출력.json> [--scale N]   한 쪽을 그리거나 레이어 트리 JSON 저장
  rhwp-render <문서> --all <출력폴더> [--pages 1-8] [--scale N] [--json <폴더>]
                                                                    여러 쪽을 page-001.png 형식으로 저장(쪽은 1부터).
                                                                    --json 을 주면 쪽마다 레이어 트리 JSON 원문도 저장
  rhwp-render --pdf <PDF> <출력폴더> [--pages 1-8] [--scale N]      기준 PDF를 같은 형식의 PNG로 래스터(배율 1 = 96dpi)
"""

var arguments = Array(CommandLine.arguments.dropFirst())

/// `--flag 값` 쌍을 인자에서 떼어 값을 돌려준다.
func takeValue(_ flag: String, from arguments: inout [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    guard index + 1 < arguments.count else { fail(usage) }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

var scale = 2.0
if let text = takeValue("--scale", from: &arguments) {
    guard let value = Double(text), value > 0 else { fail(usage) }
    scale = value
}
let jsonDirectory = takeValue("--json", from: &arguments).map { URL(fileURLWithPath: $0) }
var selection: PageSelection?
if let text = takeValue("--pages", from: &arguments) {
    guard let parsed = PageSelection(text) else { fail("쪽 목록을 해석할 수 없음: \(text)\n\(usage)") }
    selection = parsed
}

func printReport(_ report: RenderReport) {
    print("그린 op:", report.rendered.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    print("건너뛴 op:", report.skipped.isEmpty ? "없음"
          : report.skipped.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    for (requested, used) in report.fontSubstitutions.sorted(by: { $0.key < $1.key }) {
        print("글꼴 대체: \(requested) → \(used)")
    }
}

do {
    if let flagIndex = arguments.firstIndex(of: "--pdf") {
        // PDF 래스터: --pdf <PDF> <출력폴더>
        arguments.remove(at: flagIndex)
        guard arguments.count == 2 else { fail(usage) }
        let result = try PDFRaster.render(
            pdf: URL(fileURLWithPath: arguments[0]), pages: selection, scale: scale,
            into: URL(fileURLWithPath: arguments[1])
        )
        print("총 \(result.total)쪽, \(result.saved)쪽 저장: \(arguments[1])")
    } else if let flagIndex = arguments.firstIndex(of: "--all") {
        // 여러 쪽: <문서> --all <출력폴더>
        arguments.remove(at: flagIndex)
        guard arguments.count == 2 else { fail(usage) }
        let session = try await RhwpDocumentSession.open(contentsOf: URL(fileURLWithPath: arguments[0]))
        let total = try await session.pageCount()
        let directory = URL(fileURLWithPath: arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let renderer = PageRenderer()
        var merged = RenderReport()
        var saved = 0
        for number in 1...max(total, 1) where total > 0 && (selection?.contains(number) ?? true) {
            let json = try await session.layerTreeJSON(page: number - 1)
            if let jsonDirectory {
                try FileManager.default.createDirectory(at: jsonDirectory, withIntermediateDirectories: true)
                try json.write(to: jsonDirectory.appendingPathComponent(String(format: "page-%03d.json", number)))
            }
            let tree = try PageLayerTree.decode(envelope: json)
            let rendered = try renderer.render(tree, scale: scale)
            guard let png = rendered.pngData() else { fail("\(number)쪽 PNG 인코딩 실패") }
            try png.write(to: directory.appendingPathComponent(String(format: "page-%03d.png", number)))
            merged.merge(rendered.report)
            saved += 1
        }
        print("총 \(total)쪽, \(saved)쪽 저장: \(arguments[1])")
        printReport(merged)
    } else {
        // 한 쪽: <문서> <쪽(0부터)> <출력.png|출력.json>
        guard arguments.count == 3, let page = Int(arguments[1]), page >= 0 else { fail(usage) }
        let outputURL = URL(fileURLWithPath: arguments[2])
        let session = try await RhwpDocumentSession.open(contentsOf: URL(fileURLWithPath: arguments[0]))

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
            print("PNG 저장: \(outputURL.path) (\(rendered.image.width)x\(rendered.image.height), 재생 \(elapsed))")
            printReport(rendered.report)
        }
    }
} catch {
    fail("\(error.localizedDescription)")
}

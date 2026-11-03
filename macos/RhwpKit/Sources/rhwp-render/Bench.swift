import CoreGraphics
import Foundation
import RhwpKit
import RhwpRender

#if canImport(Darwin)
import Darwin
#endif

/// 큰 쪽의 디코딩·렌더 시간과 메모리를 재는 `--bench` 모드.
///
/// 뷰어가 쪽 하나에 쓰는 일을 단계별로 나눠 잰다: ① 엔진이 레이어 트리 JSON을 만든다(문서 큐), ② JSON을 `PageLayerTree`로
/// 디코딩한다, ③ 쪽을 통째로 그린다, ④ 타일 한 장을 그린다. ①과 ②를 따로 재는 이유는 디코딩을 문서 큐 밖으로 옮길지
/// 정하기 위해서다(문서 큐에서 디코딩하는 동안 같은 문서의 다른 쪽 JSON 요청이 기다린다).
///
/// 반드시 **릴리스 빌드**(`swift run -c release rhwp-render --bench …`)로 잰다. 디버그 빌드의 JSON 디코딩은 한 자릿수 배 느리다.
enum Bench {
    struct Row {
        var page: Int
        var json: Int
        var fetchMs: Double
        var decodeMs: Double
        var ops: Int
        var treeFootprintMB: Double
        var pixelWidth: Int
        var pixelHeight: Int
        var renderMs: Double?
        var tileMs: Double
        var renderPeakMB: Double?
    }

    /// 프로세스의 현재 물리 메모리 사용량(MB). `task_vm_info.phys_footprint`는 활동 모니터의 "메모리" 값과 같다.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func run(document: URL, pages: PageSelection?, scale: Double, tileSize: Int) async throws {
        let session = try await RhwpDocumentSession.open(contentsOf: document)
        let total = try await session.pageCount()
        let renderer = PageRenderer()
        let clock = ContinuousClock()
        print("문서: \(document.lastPathComponent), \(total)쪽, 배율 \(scale), 타일 \(tileSize)px")
        print("쪽 | JSON KB | 엔진 ms(첫 호출) | 디코딩 ms | op | 트리 MB | 비트맵 px | 통째 ms | 통째 최대 MB | 타일 ms")

        for number in 1...max(total, 1) where total > 0 && (pages?.contains(number) ?? true) {
            // 첫 호출이 엔진이 쪽을 조판해 레이어 트리를 만드는 실제 비용이다(문서의 첫 쪽은 문서 전체 쪽 나눔을 포함할 수 있다).
            let fetchStarted = clock.now
            let json = try await session.layerTreeJSON(page: number - 1)
            let fetch = clock.now - fetchStarted

            let before = footprintMB()
            let decodeStarted = clock.now
            let tree = try PageLayerTree.decode(envelope: json)
            let decode = clock.now - decodeStarted
            let treeFootprint = footprintMB() - before

            let grid = TileGrid(pageWidth: tree.pageWidth, pageHeight: tree.pageHeight, scale: scale, tileSize: tileSize)
            // 쪽 가운데 타일 하나(글자가 가장 많은 곳).
            let middle = TileIndex(column: grid.columns / 2, row: grid.rows / 2)
            var tileMs = Double.nan
            if let rect = grid.rect(of: middle) {
                let started = clock.now
                _ = try renderer.renderTile(tree, scale: scale, tile: rect)
                tileMs = milliseconds(clock.now - started)
            }

            // 통째 렌더는 한 변 16384px 이하일 때만 된다.
            var renderMs: Double?
            var peak: Double?
            if tree.pageWidth * scale <= 16384, tree.pageHeight * scale <= 16384 {
                let base = footprintMB()
                let started = clock.now
                let rendered = try renderer.render(tree, scale: scale)
                renderMs = milliseconds(clock.now - started)
                peak = footprintMB() - base
                _ = rendered.image.width
            }

            let row = Row(
                page: number, json: json.count, fetchMs: milliseconds(fetch), decodeMs: milliseconds(decode),
                ops: countOps(tree.root), treeFootprintMB: treeFootprint, pixelWidth: grid.pixelWidth,
                pixelHeight: grid.pixelHeight, renderMs: renderMs, tileMs: tileMs, renderPeakMB: peak
            )
            print(format(row))
        }
    }

    static func format(_ row: Row) -> String {
        func f(_ value: Double?, _ digits: Int = 1) -> String {
            guard let value, value.isFinite else { return "-" }
            return String(format: "%.\(digits)f", value)
        }
        return "\(row.page) | \(row.json / 1024) | \(f(row.fetchMs)) | \(f(row.decodeMs)) | \(row.ops) | \(f(row.treeFootprintMB)) | "
            + "\(row.pixelWidth)x\(row.pixelHeight) | \(f(row.renderMs)) | \(f(row.renderPeakMB)) | \(f(row.tileMs))"
    }

    private static func countOps(_ node: LayerNode) -> Int {
        switch node.content {
        case let .group(_, children): children.reduce(0) { $0 + countOps($1) }
        case let .clip(_, _, child): countOps(child)
        case let .leaf(ops): ops.count
        case .unsupported: 0
        }
    }
}

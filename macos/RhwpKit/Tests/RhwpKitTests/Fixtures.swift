import Foundation
import Testing

@testable import RhwpKit

/// 테스트 입력. 파일이 없으면 건너뛰지 않고 실패시킨다(조용한 통과로 검사 0건이 되는 것을 막는다).
enum Fixtures {
    /// 저장소 루트: Tests/RhwpKitTests/<이 파일> → RhwpKitTests → Tests → RhwpKit → macos → 저장소.
    static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static func sample(_ name: String) throws -> URL {
        let url = repoRoot.appendingPathComponent("samples").appendingPathComponent(name)
        try #require(FileManager.default.fileExists(atPath: url.path), "샘플 파일 없음: \(url.path)")
        return url
    }

    static func openSession(_ name: String) async throws -> RhwpDocumentSession {
        try await RhwpDocumentSession.open(contentsOf: sample(name))
    }
}

extension LayerNode {
    /// 트리를 그리는 순서대로 훑어 모든 op를 모은다.
    var allOps: [PaintOp] {
        switch content {
        case let .group(_, children): children.flatMap(\.allOps)
        case let .clip(_, _, child): child.allOps
        case let .leaf(ops): ops
        case .unsupported: []
        }
    }
}

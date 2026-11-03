import Foundation
import Testing

@testable import RhwpKit

@Suite("RhwpDocumentSession")
struct SessionTests {
    @Test("KTX.hwp는 한컴 PDF와 같은 27쪽이다")
    func pageCountMatchesHancomPDF() async throws {
        // 27쪽은 이 엔진의 출력이 아니라 한컴이 출력한 pdf/KTX-2022.pdf의 쪽수다.
        let session = try await Fixtures.openSession("KTX.hwp")
        #expect(try await session.pageCount() == 27)
    }

    @Test("데이터로 열어도 파일 경로로 연 것과 같다")
    func openDataEqualsOpenURL() async throws {
        let url = try Fixtures.sample("KTX.hwp")
        let fromData = try await RhwpDocumentSession.open(data: Data(contentsOf: url))
        let fromURL = try await RhwpDocumentSession.open(contentsOf: url)
        #expect(try await fromData.pageCount() == fromURL.pageCount())
        #expect(try await fromData.layerTreeJSON(page: 2) == fromURL.layerTreeJSON(page: 2))
    }

    @Test("쪽 범위 밖은 pageOutOfRange로 구분된다", arguments: [-1, 27, 1000])
    func pageOutOfRange(page: Int) async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        await #expect(throws: RhwpError.pageOutOfRange(page: page, pageCount: 27)) {
            _ = try await session.layerTree(page: page)
        }
    }

    @Test("없는 파일은 openFailed")
    func missingFile() async {
        let url = URL(fileURLWithPath: "/nonexistent/rhwp.hwp")
        await #expect {
            _ = try await RhwpDocumentSession.open(contentsOf: url)
        } throws: { error in
            guard case .openFailed = error as? RhwpError else { return false }
            return true
        }
    }

    @Test("HWP가 아닌 바이트는 openFailed")
    func garbageData() async {
        await #expect {
            _ = try await RhwpDocumentSession.open(data: Data("not a hwp file".utf8))
        } throws: { error in
            guard case .openFailed = error as? RhwpError else { return false }
            return true
        }
    }

    @Test("한 세션에 여러 작업이 동시에 질의해도 직렬 질의와 같은 결과다")
    func concurrentQueriesMatchSerial() async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        let pages = Array(0..<8)

        var serial: [Int: Data] = [:]
        for page in pages { serial[page] = try await session.layerTreeJSON(page: page) }

        let concurrent = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            // 같은 쪽을 두 번씩 보내 캐시된 결과와 새 결과가 섞이지 않는지도 본다.
            for page in pages + pages {
                group.addTask { (page, try await session.layerTreeJSON(page: page)) }
            }
            var results: [(Int, Data)] = []
            for try await result in group { results.append(result) }
            return results
        }

        #expect(concurrent.count == pages.count * 2)
        for (page, json) in concurrent {
            #expect(json == serial[page], "쪽 \(page)의 동시 질의 결과가 직렬 결과와 다름")
        }
    }

    @Test("서로 다른 세션은 독립적이다")
    func sessionsAreIndependent() async throws {
        let ktx = try await Fixtures.openSession("KTX.hwp")
        let table = try await Fixtures.openSession("21868765_별표2_보건소_분장사무.hwp")
        // 보건소 문서는 한컴 PDF(samples/*.pdf)가 4쪽이다.
        #expect(try await table.pageCount() == 4)
        #expect(try await ktx.pageCount() == 27)
        #expect(try await table.layerTree(page: 3).pageWidth > 0)
    }
}

@Suite("쪽 크기")
struct PageSizeTests {
    @Test("쪽 크기는 쪽수와 같은 개수이고 A4 규격이다")
    func a4PageSizes() async throws {
        let session = try await Fixtures.openSession("KTX.hwp")
        let sizes = try await session.pageSizes()
        #expect(sizes.count == 27)
        // A4(210×297mm)를 96dpi px로 바꾼 값. 엔진 출력이 아니라 용지 규격에서 정한 기대값이다.
        let first = try #require(sizes.first)
        #expect(abs(first.width - 793.70) < 0.05)
        #expect(abs(first.height - 1122.52) < 0.05)
    }

    @Test("쪽 크기는 모든 쪽의 레이어 트리 크기와 같다", arguments: ["KTX.hwp", "exam_math.hwp", "21868765_별표2_보건소_분장사무.hwp"])
    func matchesEveryLayerTree(name: String) async throws {
        let session = try await Fixtures.openSession(name)
        let sizes = try await session.pageSizes()
        #expect(sizes.count == (try await session.pageCount()))
        for (page, size) in sizes.enumerated() {
            let tree = try await session.layerTree(page: page)
            #expect(abs(size.width - tree.pageWidth) < 0.001, "\(name) \(page)쪽 너비")
            #expect(abs(size.height - tree.pageHeight) < 0.001, "\(name) \(page)쪽 높이")
        }
    }

    @Test("pages 개수가 pageCount와 다른 응답은 스키마 위반으로 실패한다")
    func rejectsMismatchedCount() {
        let json = Data(#"{"ok":true,"pageCount":3,"pages":[{"width":1,"height":2}]}"#.utf8)
        #expect {
            _ = try NativeEnvelope.decodePageSizes(from: json)
        } throws: { error in
            guard case .malformedResponse = error as? RhwpError else { return false }
            return true
        }
    }

    @Test("오류 봉투는 native 오류로 전달된다")
    func errorEnvelope() {
        let json = Data(#"{"ok":false,"error":"문서 핸들이 null입니다."}"#.utf8)
        #expect(throws: RhwpError.native("문서 핸들이 null입니다.")) {
            _ = try NativeEnvelope.decodePageSizes(from: json)
        }
    }
}

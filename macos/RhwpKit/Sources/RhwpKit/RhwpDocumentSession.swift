import Dispatch
import Foundation

/// 열린 문서 하나에 대한 Swift 동시성 창구.
///
/// - **직렬화:** 네이티브 핸들은 스레드 안전을 약속하지 않으므로 모든 네이티브 호출은 이 actor 안에서만 일어난다.
/// - **전용 실행자:** 파싱과 쪽 조판은 수십 ms 이상 걸릴 수 있어, 협력 스레드 풀을 막지 않도록 actor를
///   문서마다 하나씩 만든 직렬 큐 위에서 실행한다. 문서를 연 스레드와 쓰는 스레드도 항상 같아진다.
///   (Rust 쪽은 스레드를 옮겨도 결과가 같음을 테스트로 보장하지만, 이 구조가 그 계약에 기대지 않게 해 준다.)
/// - **수명:** 세션이 사라지면 네이티브 핸들이 해제된다.
public actor RhwpDocumentSession {
    private let handle: NativeDocumentHandle
    private let queue: DispatchSerialQueue

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private init(handle: NativeDocumentHandle, queue: DispatchSerialQueue) {
        self.handle = handle
        self.queue = queue
    }

    // MARK: - 열기

    /// 파일을 연다. 파일은 Swift에서 읽는다(샌드박스·파일 코디네이션과 맞는 경로이며, 읽기 실패도 여기서 보고한다).
    public static func open(contentsOf url: URL) async throws -> RhwpDocumentSession {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw RhwpError.openFailed("파일을 읽을 수 없습니다 - \(url.path): \(error.localizedDescription)")
        }
        return try await open(data: data)
    }

    /// 메모리의 HWP/HWPX/HWP3 파일 내용으로 연다.
    public static func open(data: Data) async throws -> RhwpDocumentSession {
        let queue = DispatchSerialQueue(label: "dev.rhwp-mac.document-session", qos: .userInitiated)
        // 파싱도 이 문서의 전용 큐에서 한다. 이후 모든 호출이 같은 스레드에서 일어난다.
        let handle = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NativeDocumentHandle, Error>) in
            queue.async {
                continuation.resume(with: Result { try NativeDocumentHandle.open(data: data) })
            }
        }
        return RhwpDocumentSession(handle: handle, queue: queue)
    }

    // MARK: - 질의

    /// 전체 쪽수.
    public func pageCount() throws -> Int {
        assertOnOwnQueue()
        return try handle.pageCount()
    }

    /// 한 쪽(0부터)의 레이어 트리.
    public func layerTree(page: Int) throws -> PageLayerTree {
        try NativeEnvelope.decodeLayerTree(from: layerTreeJSON(page: page))
    }

    /// 한 쪽(0부터)의 레이어 트리 응답 원문(JSON 봉투). 진단·골든 비교용이다.
    public func layerTreeJSON(page: Int) throws -> Data {
        assertOnOwnQueue()
        let count = try handle.pageCount()
        guard page >= 0, page < count else {
            throw RhwpError.pageOutOfRange(page: page, pageCount: count)
        }
        return try handle.pageLayerTreeJSON(page: UInt32(page))
    }

    /// 모든 네이티브 호출이 이 문서의 전용 큐 위에서 일어나는지 확인한다.
    /// `unownedExecutor`가 어긋나면(예: 실행자 연결이 빠지면) 협력 스레드 풀에서 네이티브가 호출되므로 즉시 멈춘다.
    private func assertOnOwnQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
    }
}

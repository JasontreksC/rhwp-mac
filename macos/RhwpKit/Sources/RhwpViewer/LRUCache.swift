import Foundation

/// 비용 상한이 있는 가장 오래 쓰지 않은 항목부터 버리는 캐시.
///
/// 쪽 그림은 크다(A4 @2x ≈ 14MB). 스크롤로 지나간 쪽을 모두 들고 있으면 메모리가 늘기만 하므로, 그림의 바이트
/// 수를 비용으로 삼아 상한을 넘으면 오래된 것부터 내보낸다. 값 타입이라 호출자(뷰 모델)가 격리를 책임진다.
public struct LRUCache<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var cost: Int
        var tick: UInt64
    }

    public let costLimit: Int
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    public private(set) var totalCost = 0

    public init(costLimit: Int) {
        self.costLimit = costLimit
    }

    public var count: Int { entries.count }

    /// 값을 읽고 최근에 쓴 것으로 표시한다.
    public mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock += 1
        entry.tick = clock
        entries[key] = entry
        return entry.value
    }

    /// 값을 넣는다. 상한을 넘으면 가장 오래 쓰지 않은 항목부터 내보낸다.
    /// 비용이 상한보다 큰 값은 넣지 않는다(넣자마자 자기 자신을 내보내는 일을 막는다).
    public mutating func insert(_ value: Value, cost: Int, for key: Key) {
        if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
        guard cost <= costLimit else { return }
        clock += 1
        entries[key] = Entry(value: value, cost: cost, tick: clock)
        totalCost += cost
        while totalCost > costLimit, let oldest = entries.min(by: { $0.value.tick < $1.value.tick }) {
            entries.removeValue(forKey: oldest.key)
            totalCost -= oldest.value.cost
        }
    }

    public mutating func removeAll() {
        entries.removeAll()
        totalCost = 0
    }
}

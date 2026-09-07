import Foundation

/// A bounded least-recently-used cache.
///
/// Entries carry a `cost` so the artwork cache can budget in bytes rather than
/// entry count — cover images range from a few KB to several MB, which makes a
/// count a poor proxy for memory. Metadata entries just use the default cost of
/// 1, so their limit is an entry count.
///
/// A value type with no locking of its own: it is used from inside an actor,
/// which already serialises access.
struct LRUCache<Key: Hashable, Value> {
    private var entries: [Key: (value: Value, cost: Int)] = [:]
    /// Keys in use order, least-recently-used first.
    private var order: [Key] = []

    let costLimit: Int
    private(set) var totalCost = 0

    init(costLimit: Int) {
        self.costLimit = costLimit
    }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    /// Reading counts as a use, so the getter has to mutate the recency order.
    subscript(key: Key) -> Value? {
        mutating get {
            guard let entry = entries[key] else { return nil }
            touch(key)
            return entry.value
        }
    }

    mutating func set(_ value: Value, forKey key: Key, cost: Int = 1) {
        if let existing = entries.removeValue(forKey: key) {
            totalCost -= existing.cost
            order.removeAll { $0 == key }
        }
        entries[key] = (value, max(0, cost))
        order.append(key)
        totalCost += max(0, cost)
        evictIfNeeded()
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        totalCost = 0
    }

    private mutating func touch(_ key: Key) {
        guard let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        order.append(key)
    }

    /// Drops least-recently-used entries until the budget is met. An entry
    /// larger than the whole budget evicts itself and simply isn't cached,
    /// rather than spinning.
    private mutating func evictIfNeeded() {
        while totalCost > costLimit, let oldest = order.first {
            order.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) {
                totalCost -= removed.cost
            }
        }
    }
}

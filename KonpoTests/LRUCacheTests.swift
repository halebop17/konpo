import Testing
import Foundation
@testable import Konpo

struct LRUCacheTests {

    @Test("Stores and returns values")
    func roundTrip() {
        var cache = LRUCache<String, Int>(costLimit: 10)
        cache.set(1, forKey: "a")
        cache.set(2, forKey: "b")
        #expect(cache["a"] == 1)
        #expect(cache["b"] == 2)
        #expect(cache["missing"] == nil)
        #expect(cache.count == 2)
    }

    @Test("Evicts the least recently used entry once over budget")
    func evictsOldest() {
        var cache = LRUCache<String, Int>(costLimit: 3)
        cache.set(1, forKey: "a")
        cache.set(2, forKey: "b")
        cache.set(3, forKey: "c")
        cache.set(4, forKey: "d")
        #expect(cache["a"] == nil)
        #expect(cache.count == 3)
        #expect(cache["d"] == 4)
    }

    @Test("Reading an entry protects it from the next eviction")
    func readCountsAsUse() {
        var cache = LRUCache<String, Int>(costLimit: 3)
        cache.set(1, forKey: "a")
        cache.set(2, forKey: "b")
        cache.set(3, forKey: "c")
        _ = cache["a"]           // "a" is now the most recently used
        cache.set(4, forKey: "d")
        #expect(cache["a"] == 1)  // survived
        #expect(cache["b"] == nil) // evicted instead
    }

    @Test("Re-setting a key updates the value without double-counting cost")
    func overwrite() {
        var cache = LRUCache<String, Int>(costLimit: 100)
        cache.set(1, forKey: "a", cost: 10)
        cache.set(2, forKey: "a", cost: 20)
        #expect(cache["a"] == 2)
        #expect(cache.count == 1)
        #expect(cache.totalCost == 20)
    }

    /// The artwork cache budgets in bytes, so eviction has to follow cost rather
    /// than entry count.
    @Test("Eviction follows cost, not entry count")
    func costBudget() {
        var cache = LRUCache<String, String>(costLimit: 100)
        cache.set("small", forKey: "a", cost: 10)
        cache.set("big", forKey: "b", cost: 80)
        #expect(cache.totalCost == 90)
        cache.set("another", forKey: "c", cost: 50)
        // "a" then "b" go until the 50-cost entry fits.
        #expect(cache["c"] == "another")
        #expect(cache.totalCost <= 100)
    }

    @Test("An entry larger than the whole budget is dropped, not looped on")
    func oversizedEntry() {
        var cache = LRUCache<String, String>(costLimit: 100)
        cache.set("ok", forKey: "a", cost: 50)
        cache.set("huge", forKey: "b", cost: 500)
        #expect(cache.totalCost <= 100)
        #expect(cache["b"] == nil)
    }

    @Test("removeAll resets contents and cost")
    func clear() {
        var cache = LRUCache<String, Int>(costLimit: 10)
        cache.set(1, forKey: "a", cost: 5)
        cache.removeAll()
        #expect(cache.isEmpty)
        #expect(cache.totalCost == 0)
        #expect(cache["a"] == nil)
    }
}

struct AlbumSearchNameTests {

    @Test("searchName is the lowercased display name")
    func searchName() {
        let album = Album(folderURL: URL(fileURLWithPath: "/m/OK Computer"),
                          name: "OK Computer", discs: [])
        #expect(album.searchName == "ok computer")
    }
}

import Foundation
import XCTest
@testable import Playtivity

final class LRUCacheTests: XCTestCase {
    func testPutAndGetReturnsValue() {
        let cache = LRUCache<String, Int>(maxSize: 3)
        cache.put("a", 1)
        XCTAssertEqual(cache.get("a"), 1)
    }

    func testGetReturnsNilForMissingKey() {
        let cache = LRUCache<String, Int>(maxSize: 3)
        XCTAssertNil(cache.get("missing"))
    }

    func testCapacityBoundaryExactlyAtMaxSizeDoesNotEvict() {
        let cache = LRUCache<String, Int>(maxSize: 2)
        cache.put("a", 1)
        cache.put("b", 2)
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.get("a"), 1)
        XCTAssertEqual(cache.get("b"), 2)
    }

    func testEvictsLeastRecentlyUsedWhenAtCapacity() {
        let cache = LRUCache<String, Int>(maxSize: 2)
        cache.put("a", 1)
        cache.put("b", 2)
        cache.put("c", 3) // "a" is least recently used, must be evicted
        XCTAssertNil(cache.get("a"))
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.get("c"), 3)
        XCTAssertEqual(cache.count, 2)
    }

    func testGetPromotesKeyToMostRecentlyUsed() {
        let cache = LRUCache<String, Int>(maxSize: 2)
        cache.put("a", 1)
        cache.put("b", 2)
        _ = cache.get("a") // "a" is now most-recently-used, "b" becomes least-recently-used
        cache.put("c", 3) // must evict "b", not "a"
        XCTAssertEqual(cache.get("a"), 1)
        XCTAssertNil(cache.get("b"))
        XCTAssertEqual(cache.get("c"), 3)
    }

    func testPutExistingKeyUpdatesValueWithoutEvictingAnything() {
        let cache = LRUCache<String, Int>(maxSize: 2)
        cache.put("a", 1)
        cache.put("b", 2)
        cache.put("a", 99)
        XCTAssertEqual(cache.get("a"), 99)
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.count, 2)
    }

    func testPutExistingKeyAlsoPromotesItToMostRecentlyUsed() {
        let cache = LRUCache<String, Int>(maxSize: 2)
        cache.put("a", 1)
        cache.put("b", 2)
        cache.put("a", 99) // re-putting "a" should make "b" the least-recently-used one
        cache.put("c", 3)
        XCTAssertEqual(cache.get("a"), 99)
        XCTAssertNil(cache.get("b"))
    }

    func testRemoveDeletesEntryAndReturnsItsValue() {
        let cache = LRUCache<String, Int>(maxSize: 2)
        cache.put("a", 1)
        let removed = cache.remove("a")
        XCTAssertEqual(removed, 1)
        XCTAssertNil(cache.get("a"))
        XCTAssertEqual(cache.count, 0)
    }

    func testRemoveMissingKeyReturnsNil() {
        let cache = LRUCache<String, Int>(maxSize: 2)
        XCTAssertNil(cache.remove("missing"))
    }

    func testRemoveThenPutDoesNotEvictAnythingElse() {
        let cache = LRUCache<String, Int>(maxSize: 2)
        cache.put("a", 1)
        cache.put("b", 2)
        _ = cache.remove("a")
        cache.put("c", 3)
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.get("c"), 3)
        XCTAssertEqual(cache.count, 2)
    }

    func testClearRemovesAllEntries() {
        let cache = LRUCache<String, Int>(maxSize: 3)
        cache.put("a", 1)
        cache.put("b", 2)
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.get("a"))
        XCTAssertNil(cache.get("b"))
    }
}

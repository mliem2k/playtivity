import Foundation

/// Pure-Swift port of `lib/services/lru_cache_service.dart`'s `LRUCache<K, V>` class (get/put/
/// remove/clear, evicting the least-recently-used entry on `put` when at capacity). The Dart
/// file's `CacheServices` static singleton wrapper (track-duration/artist-details/image-URL
/// caches) is deliberately not ported: nothing in this phase needs it, those caches are a Phase 4
/// concern. Backed by a plain order array + dictionary rather than a doubly-linked list: the
/// cache sizes this type is used at are small enough that O(n) reordering on `get`/`put` is not a
/// measurable cost, and this keeps the type trivial to read and test.
final class LRUCache<Key: Hashable, Value> {
    let maxSize: Int
    private var storage: [Key: Value] = [:]
    private var order: [Key] = [] // least-recently-used first, most-recently-used last

    init(maxSize: Int) {
        precondition(maxSize > 0, "LRUCache maxSize must be > 0")
        self.maxSize = maxSize
    }

    /// Returns the value for `key`, if present, and marks it as most-recently-used.
    func get(_ key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    /// Stores `value` for `key`, evicting the least-recently-used entry first if the cache is at
    /// capacity and `key` is not already present.
    func put(_ key: Key, _ value: Value) {
        if storage[key] != nil {
            storage[key] = value
            touch(key)
            return
        }
        if storage.count >= maxSize, let lruKey = order.first {
            storage.removeValue(forKey: lruKey)
            order.removeFirst()
        }
        storage[key] = value
        order.append(key)
    }

    /// Removes `key` from the cache, returning its value if it was present.
    @discardableResult
    func remove(_ key: Key) -> Value? {
        guard let value = storage.removeValue(forKey: key) else { return nil }
        order.removeAll { $0 == key }
        return value
    }

    /// Removes every entry from the cache.
    func clear() {
        storage.removeAll()
        order.removeAll()
    }

    var count: Int { storage.count }

    /// A snapshot of every key-value pair currently in the cache (in no particular order), for
    /// callers that need to persist or enumerate the full contents (e.g. `BuddyActivityService`'s
    /// artist-details cache, saved to `UserDefaults`).
    var snapshot: [Key: Value] { storage }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

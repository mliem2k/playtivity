// test/services/lru_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/services/lru_cache_service.dart';

void main() {
  group('LRUCache', () {
    late LRUCache<String, int> cache;

    setUp(() => cache = LRUCache<String, int>(3));

    test('returns null for cache miss', () {
      expect(cache.get('missing'), isNull);
    });

    test('returns value for cache hit', () {
      cache.put('a', 1);
      expect(cache.get('a'), 1);
    });

    test('evicts least recently used when at capacity', () {
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      // 'a' is LRU — inserting 'd' should evict 'a'
      cache.put('d', 4);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
      expect(cache.get('d'), 4);
    });

    test('accessing a key promotes it to MRU', () {
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      // Access 'a' to make it MRU — 'b' becomes LRU
      cache.get('a');
      cache.put('d', 4);
      expect(cache.get('a'), 1); // still present
      expect(cache.get('b'), isNull); // evicted
    });

    test('updating existing key does not change size', () {
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('a', 99); // update
      expect(cache.length, 2);
      expect(cache.get('a'), 99);
    });

    test('remove deletes key', () {
      cache.put('a', 1);
      cache.remove('a');
      expect(cache.get('a'), isNull);
      expect(cache.length, 0);
    });

    test('clear empties cache', () {
      cache.put('a', 1);
      cache.put('b', 2);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.isEmpty, isTrue);
    });

    test('containsKey returns correct results', () {
      cache.put('a', 1);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('z'), isFalse);
    });

    test('utilizationPercent is correct', () {
      cache.put('a', 1);
      // 1 / 3 = 33.33...%
      expect(cache.utilizationPercent, closeTo(33.33, 0.1));
    });

    test('throws AssertionError for maxSize of 0', () {
      expect(() => LRUCache<String, int>(0), throwsA(isA<AssertionError>()));
    });
  });

  group('CacheServices', () {
    setUp(() => CacheServices.clearAllCaches());

    test('trackDurationCache is accessible', () {
      CacheServices.trackDurationCache.put('track1', 3000);
      expect(CacheServices.trackDurationCache.get('track1'), 3000);
    });

    test('artistDetailsCache is accessible', () {
      CacheServices.artistDetailsCache.put('artist1', {'name': 'Radiohead'});
      expect(CacheServices.artistDetailsCache.get('artist1'), {'name': 'Radiohead'});
    });

    test('clearAllCaches empties all caches', () {
      CacheServices.trackDurationCache.put('t1', 1000);
      CacheServices.artistDetailsCache.put('a1', {'name': 'X'});
      CacheServices.clearAllCaches();
      expect(CacheServices.trackDurationCache.isEmpty, isTrue);
      expect(CacheServices.artistDetailsCache.isEmpty, isTrue);
    });
  });
}

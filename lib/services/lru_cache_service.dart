import 'dart:collection';
import '../services/app_logger.dart';

/// High-performance LRU (Least Recently Used) cache implementation
/// Prevents memory bloat by limiting cache size and automatically evicting old entries
class LRUCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();
  
  LRUCache(this.maxSize) : assert(maxSize > 0);
  
  /// Gets value from cache and marks it as recently used
  V? get(K key) {
    if (!_cache.containsKey(key)) {
      return null;
    }
    
    // Move to end (most recently used)
    final value = _cache.remove(key);
    _cache[key] = value!;
    return value;
  }
  
  /// Puts value in cache, evicting least recently used item if necessary
  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      // Update existing key - move to end
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
      // Evict least recently used (first item)
      final lruKey = _cache.keys.first;
      _cache.remove(lruKey);
      AppLogger.debug('LRU cache evicted key: $lruKey');
    }
    
    _cache[key] = value;
  }
  
  /// Removes specific key from cache
  V? remove(K key) {
    return _cache.remove(key);
  }
  
  /// Clears all cache entries
  void clear() {
    _cache.clear();
    AppLogger.debug('LRU cache cleared');
  }
  
  /// Gets current cache size
  int get length => _cache.length;
  
  /// Checks if cache contains key
  bool containsKey(K key) => _cache.containsKey(key);
  
  /// Gets all keys (ordered from least to most recently used)
  Iterable<K> get keys => _cache.keys;
  
  /// Gets all values (ordered from least to most recently used)
  Iterable<V> get values => _cache.values;
  
  /// Gets cache utilization as percentage
  double get utilizationPercent => (_cache.length / maxSize) * 100;
  
  /// Checks if cache is empty
  bool get isEmpty => _cache.isEmpty;
  
  /// Checks if cache is not empty
  bool get isNotEmpty => _cache.isNotEmpty;
}

/// Specialized cache services for common data types
class CacheServices {
  static final LRUCache<String, int> _trackDurationCache = LRUCache<String, int>(500);
  static final LRUCache<String, Map<String, dynamic>> _artistDetailsCache = LRUCache<String, Map<String, dynamic>>(200);
  static final LRUCache<String, String> _imageUrlCache = LRUCache<String, String>(300);
  
  /// Track duration cache with automatic memory management
  static LRUCache<String, int> get trackDurationCache => _trackDurationCache;
  
  /// Artist details cache with automatic memory management  
  static LRUCache<String, Map<String, dynamic>> get artistDetailsCache => _artistDetailsCache;
  
  /// Image URL cache for faster lookups
  static LRUCache<String, String> get imageUrlCache => _imageUrlCache;
  
  /// Logs cache statistics for monitoring
  static void logCacheStats() {
    AppLogger.debug('''Cache Statistics:
Track Duration Cache: ${_trackDurationCache.length}/${500} (${_trackDurationCache.utilizationPercent.toStringAsFixed(1)}%)
Artist Details Cache: ${_artistDetailsCache.length}/${200} (${_artistDetailsCache.utilizationPercent.toStringAsFixed(1)}%)
Image URL Cache: ${_imageUrlCache.length}/${300} (${_imageUrlCache.utilizationPercent.toStringAsFixed(1)}%)''');
  }
  
  /// Clears all caches (useful for memory cleanup)
  static void clearAllCaches() {
    _trackDurationCache.clear();
    _artistDetailsCache.clear();
    _imageUrlCache.clear();
    AppLogger.debug('All LRU caches cleared');
  }
}
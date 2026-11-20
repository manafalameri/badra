/// Simple in-memory cache with TTL for shared data between screens.
class DataCache {
  static final DataCache _instance = DataCache._internal();
  factory DataCache() => _instance;
  DataCache._internal();

  static const Duration _defaultTtl = Duration(seconds: 30);

  final Map<String, _CacheEntry> _cache = {};

  /// Get cached value if not expired, otherwise null.
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) {
      return entry.value as T;
    }
    if (entry != null) {
      _cache.remove(key);
    }
    return null;
  }

  /// Set cache value with TTL.
  void set<T>(String key, T value, {Duration? ttl}) {
    _cache[key] = _CacheEntry(value, ttl ?? _defaultTtl);
  }

  /// Invalidate a specific key.
  void invalidate(String key) {
    _cache.remove(key);
  }

  /// Clear all cache.
  void clear() {
    _cache.clear();
  }

  /// Invalidate keys matching a prefix.
  void invalidatePrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }
}

class _CacheEntry {
  final dynamic value;
  final DateTime expiresAt;

  _CacheEntry(this.value, Duration ttl) : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
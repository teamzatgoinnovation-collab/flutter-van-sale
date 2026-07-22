/// Simple TTL memory cache for defaults / pick lists.
class TtlMemoryCache<T> {
  TtlMemoryCache({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;
  T? _value;
  DateTime? _storedAt;

  T? get value {
    final stored = _storedAt;
    final v = _value;
    if (v == null || stored == null) return null;
    if (DateTime.now().difference(stored) > ttl) {
      clear();
      return null;
    }
    return v;
  }

  void set(T value) {
    _value = value;
    _storedAt = DateTime.now();
  }

  void clear() {
    _value = null;
    _storedAt = null;
  }

  bool get isValid => value != null;
}

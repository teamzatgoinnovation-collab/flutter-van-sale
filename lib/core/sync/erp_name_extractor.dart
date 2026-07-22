/// Extract ERPNext document name from sync / list payloads.
abstract final class ErpNameExtractor {
  static String? fromMap(
    Object? data, {
    List<String> keys = const ['erp_name', 'id', 'name'],
  }) {
    if (data is! Map) return null;
    for (final key in keys) {
      final value = data[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        return '$value'.trim();
      }
    }
    return null;
  }
}

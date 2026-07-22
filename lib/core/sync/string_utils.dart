/// Shared string helpers for draft → model mapping.
abstract final class StringUtils {
  static String? emptyToNull(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

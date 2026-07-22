/// Domain / repository validation failure (shared base).
class ValidationException implements Exception {
  ValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() => errors.join('\n');
}

import 'package:flutter/foundation.dart';

/// Lightweight structured logger for VanSale feature modules.
abstract final class AppLogger {
  static void debug(String message, {String? tag, Object? error}) {
    if (!kDebugMode) return;
    final prefix = tag == null ? '[VanSale]' : '[VanSale/$tag]';
    if (error != null) {
      debugPrint('$prefix $message · $error');
    } else {
      debugPrint('$prefix $message');
    }
  }

  static void info(String message, {String? tag}) {
    final prefix = tag == null ? '[VanSale]' : '[VanSale/$tag]';
    debugPrint('$prefix $message');
  }

  static void warn(String message, {String? tag, Object? error}) {
    final prefix = tag == null ? '[VanSale]' : '[VanSale/$tag]';
    debugPrint('$prefix WARN $message${error == null ? '' : ' · $error'}');
  }

  static void error(String message, {String? tag, Object? error, StackTrace? stack}) {
    final prefix = tag == null ? '[VanSale]' : '[VanSale/$tag]';
    debugPrint('$prefix ERROR $message${error == null ? '' : ' · $error'}');
    if (stack != null && kDebugMode) {
      debugPrint(stack.toString());
    }
  }
}

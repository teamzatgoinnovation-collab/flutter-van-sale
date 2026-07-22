import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Shared local-file → ERPNext attachment payload encoder.
abstract final class AttachmentEncoder {
  static const maxBytes = 8 * 1024 * 1024;

  /// Returns `{filename, content_b64}` or null when path missing / unreadable.
  static Future<Map<String, dynamic>?> fileMap(
    String? localPath, {
    String? key,
  }) async {
    if (localPath == null || localPath.trim().isEmpty) return null;
    final file = File(localPath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw StateError(
        key == null || key.isEmpty
            ? 'Attachment exceeds 8MB'
            : 'Attachment $key exceeds 8MB',
      );
    }
    return {
      'filename': p.basename(localPath),
      'content_b64': base64Encode(bytes),
    };
  }

  static Future<void> put(
    Map<String, dynamic> out,
    String key,
    String? localPath,
  ) async {
    final map = await fileMap(localPath, key: key);
    if (map != null) out[key] = map;
  }
}

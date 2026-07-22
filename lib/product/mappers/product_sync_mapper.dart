import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../dto/product_dto.dart';
import '../models/product_model.dart';

class ProductSyncMapper {
  const ProductSyncMapper();

  Future<Map<String, dynamic>> toSyncArgs(
    ProductModel model, {
    String? company,
  }) async {
    final attachments = <String, dynamic>{};
    await _maybeAttach(attachments, 'image', model.imagePath);
    final gallery = <Map<String, dynamic>>[];
    for (final path in model.galleryPaths) {
      final entry = await _fileMap(path);
      if (entry != null) gallery.add(entry);
    }
    if (gallery.isNotEmpty) attachments['gallery'] = gallery;

    final dto = ProductDto.fromModel(
      model,
      company: company,
      attachments: attachments,
    );
    return {
      'client_id': dto.clientId,
      'item': dto.toItemJson(),
      if (attachments.isNotEmpty) 'attachments': attachments,
    };
  }

  Future<void> _maybeAttach(
    Map<String, dynamic> out,
    String key,
    String? localPath,
  ) async {
    final map = await _fileMap(localPath);
    if (map != null) out[key] = map;
  }

  Future<Map<String, dynamic>?> _fileMap(String? localPath) async {
    if (localPath == null || localPath.trim().isEmpty) return null;
    final file = File(localPath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      throw StateError('Attachment exceeds 8MB');
    }
    return {
      'filename': p.basename(localPath),
      'content_b64': base64Encode(bytes),
    };
  }

  String? extractErpName(Object? data) {
    if (data is Map) {
      final name =
          data['erp_name'] ?? data['item_code'] ?? data['id'] ?? data['name'];
      if (name != null && '$name'.trim().isNotEmpty) return '$name'.trim();
    }
    return null;
  }
}

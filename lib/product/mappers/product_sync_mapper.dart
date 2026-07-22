import '../../core/sync/attachment_encoder.dart';
import '../../core/sync/erp_name_extractor.dart';
import '../dto/product_dto.dart';
import '../models/product_model.dart';

/// Maps domain products ↔ ERPNext Item sync method args.
class ProductSyncMapper {
  const ProductSyncMapper();

  Future<Map<String, dynamic>> toSyncArgs(
    ProductModel model, {
    String? company,
  }) async {
    final attachments = <String, dynamic>{};
    await AttachmentEncoder.put(attachments, 'image', model.imagePath);
    final gallery = <Map<String, dynamic>>[];
    for (final path in model.galleryPaths) {
      final entry = await AttachmentEncoder.fileMap(path);
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

  String? extractErpName(Object? data) => ErpNameExtractor.fromMap(
        data,
        keys: const ['erp_name', 'item_code', 'id', 'name'],
      );
}

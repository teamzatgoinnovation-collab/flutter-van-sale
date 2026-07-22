import 'package:path/path.dart' as p;

import '../../core/sync/attachment_encoder.dart';
import '../../core/sync/erp_name_extractor.dart';
import '../dto/customer_dto.dart';
import '../models/customer_model.dart';

/// Maps domain customers ↔ ERPNext sync method args.
class CustomerSyncMapper {
  const CustomerSyncMapper();

  /// Build `callMethod` args for `accounting.customers.sync`.
  Future<Map<String, dynamic>> toSyncArgs(
    CustomerModel model, {
    String? company,
  }) async {
    final attachments = <String, dynamic>{};
    await AttachmentEncoder.put(attachments, 'cr_image', model.crImagePath);
    await AttachmentEncoder.put(
      attachments,
      'vat_certificate',
      model.vatCertificatePath,
    );
    await AttachmentEncoder.put(
      attachments,
      'customer_photo',
      model.customerPhotoPath,
    );

    final dto = CustomerDto.fromModel(
      model,
      company: company,
      attachments: attachments,
    );

    return {
      'client_id': dto.clientId,
      'customer': dto.toCustomerJson(),
      'contact': dto.toContactJson(),
      'address': dto.toAddressJson(),
      if (attachments.isNotEmpty) 'attachments': attachments,
    };
  }

  String? extractErpName(Object? data) => ErpNameExtractor.fromMap(data);

  /// Kept for callers that need basename only (tests / tooling).
  static String basename(String path) => p.basename(path);
}

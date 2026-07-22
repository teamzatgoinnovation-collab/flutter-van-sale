import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../dto/customer_dto.dart';
import '../models/customer_model.dart';

/// Maps domain customers ↔ ERPNext sync method args.
class CustomerSyncMapper {
  const CustomerSyncMapper();

  /// Build `callMethod` args for `accounting.customers.sync`.
  Future<Map<String, dynamic>> toSyncArgs(CustomerModel model, {String? company}) async {
    final attachments = <String, dynamic>{};
    await _maybeAttach(attachments, 'cr_image', model.crImagePath);
    await _maybeAttach(attachments, 'vat_certificate', model.vatCertificatePath);
    await _maybeAttach(attachments, 'customer_photo', model.customerPhotoPath);

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

  Future<void> _maybeAttach(
    Map<String, dynamic> out,
    String key,
    String? localPath,
  ) async {
    if (localPath == null || localPath.trim().isEmpty) return;
    final file = File(localPath);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      throw StateError('Attachment $key exceeds 8MB');
    }
    out[key] = {
      'filename': p.basename(localPath),
      'content_b64': base64Encode(bytes),
    };
  }

  String? extractErpName(Object? data) {
    if (data is Map) {
      final name = data['erp_name'] ?? data['id'] ?? data['name'];
      if (name != null && '$name'.trim().isNotEmpty) return '$name'.trim();
    }
    return null;
  }
}

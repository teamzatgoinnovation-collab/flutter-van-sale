import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'session.dart';
import 'van_sale_api_methods.dart';

/// Fetch and open/share VanSale tax invoice PDFs.
class VanSaleInvoiceService {
  VanSaleInvoiceService(this.session);

  final VanSaleSession session;

  Future<Uint8List> fetchPdfBytes(String erpName) async {
    final env = await session.store.callMethod(
      VanSaleApiMethods.ordersPdf,
      args: {'name': erpName},
    );
    final data = env.data;
    if (data is! Map) {
      throw StateError('Invoice PDF response missing data');
    }
    final b64 = '${data['pdf_base64'] ?? ''}';
    if (b64.isEmpty) {
      throw StateError('Invoice PDF empty');
    }
    return Uint8List.fromList(base64Decode(b64));
  }

  Future<void> openPdf(String erpName) async {
    final bytes = await fetchPdfBytes(erpName);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: erpName);
  }

  Future<void> sharePdf(String erpName) async {
    final bytes = await fetchPdfBytes(erpName);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$erpName.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: erpName),
    );
  }

  static Future<void> showActions(
    BuildContext context, {
    required VanSaleSession session,
    required String erpName,
  }) async {
    final service = VanSaleInvoiceService(session);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Open invoice'),
              subtitle: Text(erpName),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share PDF'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Preparing invoice…')),
    );
    try {
      if (choice == 'open') {
        await service.openPdf(erpName);
      } else {
        await service.sharePdf(erpName);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Invoice: $e')));
    }
  }
}

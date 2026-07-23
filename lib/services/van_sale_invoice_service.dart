import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'session.dart';
import 'van_sale_api_methods.dart';

/// Fetch and print/share VanSale tax invoices & local thermal receipts with ZATCA QR codes.
class VanSaleInvoiceService {
  VanSaleInvoiceService(this.session);

  final VanSaleSession session;

  /// Generate ZATCA Phase 1 TLV-encoded Base64 QR code payload.
  static String generateZatcaTlvQrBase64({
    required String sellerName,
    required String vatNumber,
    required String timestamp,
    required String totalAmount,
    required String vatAmount,
  }) {
    final bytes = <int>[];

    void addTag(int tag, String value) {
      final valBytes = utf8.encode(value);
      bytes.add(tag);
      bytes.add(valBytes.length);
      bytes.addAll(valBytes);
    }

    addTag(1, sellerName.isEmpty ? 'ZatGo VanSale' : sellerName);
    addTag(2, vatNumber.isEmpty ? '300000000000003' : vatNumber);
    addTag(3, timestamp);
    addTag(4, totalAmount);
    addTag(5, vatAmount);

    return base64Encode(bytes);
  }

  /// Generate a local 80mm thermal receipt PDF document byte array for field sales printing.
  static Future<Uint8List> generateLocalThermalReceiptBytes({
    required String orderId,
    required String customerName,
    required String dateStr,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    String sellerName = 'ZatGo Innovation',
    String vatNumber = '300000000000003',
  }) async {
    final doc = pw.Document();

    final zatcaB64 = generateZatcaTlvQrBase64(
      sellerName: sellerName,
      vatNumber: vatNumber,
      timestamp: dateStr,
      totalAmount: grandTotal.toStringAsFixed(2),
      vatAmount: tax.toStringAsFixed(2),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(12),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  sellerName,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'VAT: $vatNumber',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'SIMPLIFIED TAX INVOICE',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Divider(thickness: 0.5),
              pw.Text('Order: #$orderId', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Customer: $customerName', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Item', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Qty x Price', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Total', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Divider(thickness: 0.5),
              ...items.map((it) {
                final name = '${it['item_name'] ?? it['item_code'] ?? 'Item'}';
                final qty = (it['qty'] as num?)?.toDouble() ?? 1.0;
                final rate = (it['rate'] as num?)?.toDouble() ?? 0.0;
                final total = qty * rate;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(name, style: const pw.TextStyle(fontSize: 8)),
                      ),
                      pw.Text('${qty.toStringAsFixed(0)} x ${rate.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(width: 8),
                      pw.Text(total.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(subtotal.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              if (discount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Discount', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('-${discount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('VAT (15%)', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(tax.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('GRAND TOTAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text(grandTotal.toStringAsFixed(2), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: zatcaB64,
                  width: 80,
                  height: 80,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'ZATCA Compliant E-Invoice',
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<Uint8List> fetchPdfBytes(String erpName) async {
    final name = erpName.trim();
    if (name.isEmpty) {
      throw StateError('Invoice name missing');
    }
    final env = await session.store.callMethod(
      VanSaleApiMethods.ordersPdf,
      args: {'name': name},
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
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: erpName.trim(),
    );
  }

  Future<void> printThermalReceipt({
    required String orderId,
    required String customerName,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
  }) async {
    final bytes = await generateLocalThermalReceiptBytes(
      orderId: orderId,
      customerName: customerName,
      dateStr: DateTime.now().toIso8601String().split('.')[0],
      items: items,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      grandTotal: grandTotal,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Receipt_$orderId',
      format: PdfPageFormat.roll80,
    );
  }

  Future<void> sharePdf(String erpName) async {
    final bytes = await fetchPdfBytes(erpName);
    final dir = await getTemporaryDirectory();
    final safe = erpName.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final file = File('${dir.path}/$safe.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: erpName.trim()),
    );
  }

  static Future<void> showActions(
    BuildContext context, {
    required VanSaleSession session,
    required String erpName,
  }) async {
    final name = erpName.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice not synced yet')),
      );
      return;
    }
    final service = VanSaleInvoiceService(session);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Open invoice PDF'),
              subtitle: Text(name),
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
        await service.openPdf(name);
      } else {
        await service.sharePdf(name);
      }
      if (context.mounted) messenger.hideCurrentSnackBar();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Invoice: $e')));
    }
  }
}

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../customer/models/customer_model.dart';
import '../customer/repositories/customer_repository.dart';
import '../customer/validation/customer_validators.dart';
import '../data/van_sale_db.dart';
import '../product/repositories/product_repository.dart';
import '../product/validation/product_validators.dart';
import 'session.dart';

class CatalogExcelResult {
  const CatalogExcelResult({
    this.created = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = const [],
  });

  final int created;
  final int updated;
  final int skipped;
  final List<String> errors;

  String get summary =>
      'Created $created · updated $updated · skipped $skipped'
      '${errors.isEmpty ? '' : ' · errors ${errors.length}'}';
}

/// Excel export/import for customers and products.
class CatalogExcelService {
  CatalogExcelService({
    VanSaleDb? db,
    CustomerRepository? customers,
    ProductRepository? products,
  }) : db = db ?? VanSaleDb.instance,
       customers = customers ?? customerRepository,
       products = products ?? productRepository;

  final VanSaleDb db;
  final CustomerRepository customers;
  final ProductRepository products;

  static const customerHeaders = [
    'customer_name',
    'customer_name_ar',
    'customer_type',
    'customer_group',
    'territory',
    'tax_id',
    'cr_number',
    'customer_code',
    'mobile_no',
    'phone',
    'email',
    'address_line1',
    'city',
    'state',
    'country',
    'postal_code',
    'price_list',
    'sales_person',
    'credit_limit',
    'payment_terms',
    'currency',
    'enabled',
    'remarks',
  ];

  static const productHeaders = [
    'item_code',
    'item_name',
    'item_name_ar',
    'item_group',
    'stock_uom',
    'barcode',
    'sku',
    'selling_rate',
    'purchase_rate',
    'brand',
    'hs_code',
    'maintain_stock',
    'disabled',
    'reorder_level',
    'opening_quantity',
    'opening_warehouse',
  ];

  Future<File> exportCustomers() async {
    final page = await customers.search(query: '', limit: 5000);
    final excel = Excel.createExcel();
    final sheet = excel['Customers'];
    excel.delete('Sheet1');
    sheet.appendRow(customerHeaders.map((h) => TextCellValue(h)).toList());
    for (final c in page.items) {
      sheet.appendRow([
        TextCellValue(c.customerName),
        TextCellValue(c.customerNameAr ?? ''),
        TextCellValue(c.customerType),
        TextCellValue(c.customerGroup),
        TextCellValue(c.territory),
        TextCellValue(c.taxId ?? ''),
        TextCellValue(c.crNumber ?? ''),
        TextCellValue(c.customerCode ?? ''),
        TextCellValue(c.mobileNo),
        TextCellValue(c.phone ?? ''),
        TextCellValue(c.email ?? ''),
        TextCellValue(c.addressLine1),
        TextCellValue(c.city),
        TextCellValue(c.state ?? ''),
        TextCellValue(c.country),
        TextCellValue(c.postalCode ?? ''),
        TextCellValue(c.priceList ?? ''),
        TextCellValue(c.salesPerson ?? ''),
        TextCellValue('${c.creditLimit ?? ''}'),
        TextCellValue(c.paymentTerms ?? ''),
        TextCellValue(c.currency ?? ''),
        TextCellValue(c.enabled ? '1' : '0'),
        TextCellValue(c.remarks ?? ''),
      ]);
    }
    return _saveExcel(excel, 'van_sale_customers');
  }

  Future<File> exportProducts() async {
    final page = await products.search(query: '', limit: 5000);
    final excel = Excel.createExcel();
    final sheet = excel['Products'];
    excel.delete('Sheet1');
    sheet.appendRow(productHeaders.map((h) => TextCellValue(h)).toList());
    for (final item in page.items) {
      sheet.appendRow([
        TextCellValue(item.itemCode),
        TextCellValue(item.itemName),
        TextCellValue(item.itemNameAr ?? ''),
        TextCellValue(item.itemGroup),
        TextCellValue(item.stockUom),
        TextCellValue(item.barcode ?? ''),
        TextCellValue(item.sku ?? ''),
        TextCellValue('${item.sellingRate}'),
        TextCellValue('${item.purchaseRate}'),
        TextCellValue(item.brand ?? ''),
        TextCellValue(item.hsCode ?? ''),
        TextCellValue(item.maintainStock ? '1' : '0'),
        TextCellValue(item.disabled ? '1' : '0'),
        TextCellValue('${item.reorderLevel ?? ''}'),
        TextCellValue('${item.openingQuantity}'),
        TextCellValue(item.openingWarehouse ?? ''),
      ]);
    }
    return _saveExcel(excel, 'van_sale_products');
  }

  Future<File> templateCustomers() async {
    final excel = Excel.createExcel();
    final sheet = excel['Customers'];
    excel.delete('Sheet1');
    sheet.appendRow(customerHeaders.map((h) => TextCellValue(h)).toList());
    return _saveExcel(excel, 'van_sale_customers_template');
  }

  Future<File> templateProducts() async {
    final excel = Excel.createExcel();
    final sheet = excel['Products'];
    excel.delete('Sheet1');
    sheet.appendRow(productHeaders.map((h) => TextCellValue(h)).toList());
    return _saveExcel(excel, 'van_sale_products_template');
  }

  Future<void> shareFile(File file, {required String subject}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  }

  Future<CustomerModel?> _findCustomerByName(String name) async {
    final page = await customers.search(query: name, limit: 20);
    for (final c in page.items) {
      if (c.customerName.toLowerCase() == name.toLowerCase() ||
          c.displayName.toLowerCase() == name.toLowerCase() ||
          (c.erpName ?? '').toLowerCase() == name.toLowerCase()) {
        return c;
      }
    }
    return null;
  }

  Future<CatalogExcelResult> importCustomers(
    File file,
    VanSaleSession session,
  ) async {
    await customers.loadDefaults(session);
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 2) {
      return const CatalogExcelResult(errors: ['No data rows']);
    }
    final header = sheet.rows.first
        .map((c) => '${c?.value ?? ''}'.trim().toLowerCase())
        .toList();
    var created = 0;
    var updated = 0;
    var skipped = 0;
    final errors = <String>[];

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      String cell(String key) {
        final idx = header.indexOf(key);
        if (idx < 0 || idx >= row.length) return '';
        return '${row[idx]?.value ?? ''}'.trim();
      }

      final name = cell('customer_name');
      if (name.isEmpty) {
        skipped++;
        continue;
      }
      try {
        final existing = await _findCustomerByName(name);
        final draft = CustomerDraft()
          ..customerName = name
          ..customerNameAr = cell('customer_name_ar')
          ..customerType = cell('customer_type')
          ..customerGroup = cell('customer_group')
          ..territory = cell('territory')
          ..taxId = cell('tax_id')
          ..crNumber = cell('cr_number')
          ..customerCode = cell('customer_code')
          ..mobileNo = cell('mobile_no')
          ..phone = cell('phone')
          ..email = cell('email')
          ..addressLine1 = cell('address_line1')
          ..city = cell('city')
          ..state = cell('state')
          ..country = cell('country')
          ..postalCode = cell('postal_code')
          ..priceList = cell('price_list')
          ..salesPerson = cell('sales_person')
          ..creditLimit = double.tryParse(cell('credit_limit'))
          ..paymentTerms = cell('payment_terms')
          ..currency = cell('currency')
          ..enabled = cell('enabled') != '0'
          ..remarks = cell('remarks');
        draft.applyDefaults(customers.defaults);
        if (draft.mobileNo.isEmpty) draft.mobileNo = '0500000000';
        if (draft.addressLine1.isEmpty) draft.addressLine1 = 'TBD';
        if (draft.city.isEmpty) draft.city = 'Riyadh';
        if (draft.country.isEmpty) draft.country = 'Saudi Arabia';
        if (existing == null) {
          await customers.createLocal(draft, session: session);
          created++;
        } else {
          await customers.updateLocal(existing.id, draft, session: session);
          updated++;
        }
      } catch (e) {
        errors.add('Row ${i + 1}: $e');
      }
    }
    return CatalogExcelResult(
      created: created,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  Future<CatalogExcelResult> importProducts(
    File file,
    VanSaleSession session,
  ) async {
    await products.loadDefaults(session);
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 2) {
      return const CatalogExcelResult(errors: ['No data rows']);
    }
    final header = sheet.rows.first
        .map((c) => '${c?.value ?? ''}'.trim().toLowerCase())
        .toList();
    var created = 0;
    var updated = 0;
    var skipped = 0;
    final errors = <String>[];

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      String cell(String key) {
        final idx = header.indexOf(key);
        if (idx < 0 || idx >= row.length) return '';
        return '${row[idx]?.value ?? ''}'.trim();
      }

      final code = cell('item_code');
      final name = cell('item_name');
      if (code.isEmpty || name.isEmpty) {
        skipped++;
        continue;
      }
      try {
        final existing = await products.findByItemCode(code);
        final draft = ProductDraft()
          ..itemCode = code
          ..itemName = name
          ..itemNameAr = cell('item_name_ar')
          ..itemGroup = cell('item_group')
          ..stockUom = cell('stock_uom')
          ..barcode = cell('barcode')
          ..sku = cell('sku')
          ..sellingRate = double.tryParse(cell('selling_rate')) ?? 0
          ..purchaseRate = double.tryParse(cell('purchase_rate')) ?? 0
          ..brand = cell('brand')
          ..hsCode = cell('hs_code')
          ..maintainStock = cell('maintain_stock') != '0'
          ..disabled = cell('disabled') == '1'
          ..reorderLevel = double.tryParse(cell('reorder_level'))
          ..openingQuantity = double.tryParse(cell('opening_quantity')) ?? 0
          ..openingWarehouse = cell('opening_warehouse');
        draft.applyDefaults(products.defaults);
        if (existing == null) {
          await products.createLocal(draft, session: session);
          created++;
        } else {
          await products.updateLocal(existing.id, draft, session: session);
          updated++;
        }
      } catch (e) {
        errors.add('Row ${i + 1}: $e');
      }
    }
    return CatalogExcelResult(
      created: created,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  Future<File> _saveExcel(Excel excel, String basename) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, '$basename.xlsx');
    final bytes = excel.encode();
    if (bytes == null) throw StateError('Failed to encode Excel');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

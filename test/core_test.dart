import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van_sale/core/cache/ttl_memory_cache.dart';
import 'package:van_sale/core/di/van_sale_services.dart';
import 'package:van_sale/core/search/paged_search_result.dart';
import 'package:van_sale/core/sync/attachment_encoder.dart';
import 'package:van_sale/core/sync/erp_name_extractor.dart';
import 'package:van_sale/core/sync/string_utils.dart';
import 'package:van_sale/customer/repositories/customer_repository.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/data/van_sale_repo.dart';
import 'package:van_sale/product/repositories/product_repository.dart';
import 'package:van_sale/services/prefs.dart';

void main() {
  test('StringUtils.emptyToNull', () {
    expect(StringUtils.emptyToNull(null), isNull);
    expect(StringUtils.emptyToNull('  '), isNull);
    expect(StringUtils.emptyToNull(' a '), 'a');
  });

  test('ErpNameExtractor prefers erp_name', () {
    expect(
      ErpNameExtractor.fromMap({'erp_name': 'C-1', 'name': 'Other'}),
      'C-1',
    );
    expect(
      ErpNameExtractor.fromMap(
        {'item_code': 'SKU'},
        keys: const ['erp_name', 'item_code', 'id', 'name'],
      ),
      'SKU',
    );
  });

  test('PagedSearchResult.append', () {
    const a = PagedSearchResult<int>(
      items: [1, 2],
      total: 4,
      limit: 2,
      offset: 0,
      hasMore: true,
    );
    const b = PagedSearchResult<int>(
      items: [3, 4],
      total: 4,
      limit: 2,
      offset: 2,
      hasMore: false,
    );
    final merged = a.append(b);
    expect(merged.items, [1, 2, 3, 4]);
    expect(merged.hasMore, isFalse);
  });

  test('TtlMemoryCache stores and clears', () {
    final cache = TtlMemoryCache<String>(ttl: const Duration(minutes: 5));
    expect(cache.value, isNull);
    cache.set('ok');
    expect(cache.value, 'ok');
    cache.clear();
    expect(cache.value, isNull);
  });

  test('AttachmentEncoder encodes existing file', () async {
    final file = File(
      '${Directory.systemTemp.path}/van_sale_attach_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    await file.writeAsString('hello');
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final map = await AttachmentEncoder.fileMap(file.path, key: 'image');
    expect(map, isNotNull);
    expect(map!['filename'], isNotEmpty);
    expect(map['content_b64'], isNotEmpty);
  });

  test('VanSaleServices bootstrap is injectable', () async {
    VanSaleServices.resetForTest(null);
    expect(VanSaleServices.isBootstrapped, isFalse);
    await VanSaleServices.bootstrap(
      db: VanSaleDb.instance,
      prefs: VanSalePrefs.instance,
      customers: customerRepository,
      products: productRepository,
      repo: vanSaleRepo,
    );
    expect(VanSaleServices.isBootstrapped, isTrue);
    expect(identical(VanSaleServices.instance.customers, customerRepository), isTrue);
    VanSaleServices.resetForTest(null);
  });
}

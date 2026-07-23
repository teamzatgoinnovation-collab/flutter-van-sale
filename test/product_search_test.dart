import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/models/models.dart';
import 'package:van_sale/product/models/product_model.dart';
import 'package:van_sale/product/repositories/product_repository.dart';
import 'package:van_sale/product/validation/product_validators.dart';
import 'package:van_sale/services/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await VanSalePrefs.instance.resetForTest();
    await VanSalePrefs.instance.setWorkMode(VanSaleWorkMode.onlineOffline);
    final db = await VanSaleDb.instance.database;
    await db.delete('sync_queue');
    await db.delete('product_favorites');
    await db.delete('product_recent');
    await db.delete('product_sales_stats');
    await db.delete('van_stock');
    await db.delete('products');
  });

  Future<ProductModel> seed({
    required String code,
    required String name,
    String? nameAr,
    String? brand,
    String? sku,
    String? barcode,
    String group = 'Products',
    double rate = 10,
    double stock = 5,
  }) async {
    final created = await productRepository.createLocal(
      ProductDraft()
        ..itemCode = code
        ..itemName = name
        ..itemNameAr = nameAr ?? ''
        ..itemGroup = group
        ..stockUom = 'Nos'
        ..brand = brand ?? ''
        ..sku = sku ?? ''
        ..barcode = barcode ?? ''
        ..sellingRate = rate
        ..openingQuantity = stock,
    );
    return created;
  }

  test('search matches code, name, arabic, sku, brand, barcode, category', () async {
    await seed(
      code: 'SKU-A',
      name: 'Widget',
      nameAr: 'أداة',
      brand: 'Acme',
      sku: 'W-1',
      barcode: 'BC111',
      group: 'Hardware',
    );
    await seed(code: 'SKU-B', name: 'Gadget', barcode: 'BC222');

    expect(
      (await productRepository.search(query: 'أداة')).items.first.itemCode,
      'SKU-A',
    );
    expect(
      (await productRepository.search(query: 'Acme')).items.first.itemCode,
      'SKU-A',
    );
    expect(
      (await productRepository.search(query: 'W-1')).items.first.itemCode,
      'SKU-A',
    );
    expect(
      (await productRepository.search(query: 'Hardware')).items.first.itemCode,
      'SKU-A',
    );
    expect(
      (await productRepository.search(query: 'BC222')).items.first.itemCode,
      'SKU-B',
    );
  });

  test('barcode, favorites, recent, frequent, pagination + stock join', () async {
    final a = await seed(code: 'P1', name: 'One', barcode: 'BAR-1', stock: 12);
    final b = await seed(code: 'P2', name: 'Two', barcode: 'BAR-2', stock: 0);
    for (var i = 0; i < 35; i++) {
      await seed(code: 'BULK$i', name: 'Bulk $i', stock: 1);
    }

    final byBc = await productRepository.findByBarcode('BAR-1');
    expect(byBc?.id, a.id);
    expect(byBc?.stockQty, 12);

    await productRepository.toggleFavorite(b.id, favorite: true);
    final favs = await productRepository.search(
      scope: ProductSearchScope.favorites,
    );
    expect(favs.items.map((e) => e.id), contains(b.id));
    expect(favs.items.firstWhere((e) => e.id == b.id).inStock, isFalse);

    await productRepository.markRecent(a.id);
    final recent = await productRepository.search(
      scope: ProductSearchScope.recent,
    );
    expect(recent.items.first.id, a.id);

    await productRepository.recordSales([
      const OrderLine(
        itemCode: 'P2',
        itemName: 'Two',
        qty: 3,
        unitPrice: 10,
      ),
      const OrderLine(
        itemCode: 'P2',
        itemName: 'Two',
        qty: 2,
        unitPrice: 10,
      ),
    ]);
    final frequent = await productRepository.search(
      scope: ProductSearchScope.frequent,
    );
    expect(frequent.items.first.itemCode, 'P2');

    final page1 = await productRepository.search(limit: 10, offset: 0);
    expect(page1.items.length, 10);
    expect(page1.hasMore, isTrue);
    expect(page1.items.first.displayPrice, greaterThanOrEqualTo(0));
  });
}

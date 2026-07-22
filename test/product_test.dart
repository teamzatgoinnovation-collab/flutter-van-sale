import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/models/models.dart';
import 'package:van_sale/product/repositories/product_repository.dart';
import 'package:van_sale/product/validation/product_validators.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = await VanSaleDb.instance.database;
    await db.delete('sync_queue');
    await db.delete('products');
    await db.delete('van_stock');
  });

  test('product validators require core fields', () {
    final errors = ProductValidators.validate(
      itemCode: '',
      itemName: '',
      itemGroup: '',
      stockUom: '',
      sellingRate: -1,
    );
    expect(errors.length, greaterThanOrEqualTo(4));
  });

  test('createLocal enqueues product sync', () async {
    final repo = ProductRepository(VanSaleDb.instance);
    final draft = ProductDraft()
      ..itemCode = 'VS-TEST-1'
      ..itemName = 'Van Sale Test'
      ..itemGroup = 'Products'
      ..stockUom = 'Nos'
      ..sellingRate = 10
      ..openingQuantity = 5
      ..openingWarehouse = 'Stores - EZ';

    final created = await repo.createLocal(draft);
    expect(created.syncStatus, SyncStatus.pending);
    final queue = await VanSaleDb.instance.peekQueue();
    expect(queue.any((q) => q.entityType == 'product'), isTrue);
    final stock = await VanSaleDb.instance.getStock('VS-TEST-1');
    expect(stock?.qty, 5);
  });

  test('duplicate item code rejected', () async {
    final repo = ProductRepository(VanSaleDb.instance);
    Future<void> make(String code) async {
      final draft = ProductDraft()
        ..itemCode = code
        ..itemName = 'X'
        ..itemGroup = 'Products'
        ..stockUom = 'Nos';
      await repo.createLocal(draft);
    }

    await make('DUP-1');
    expect(
      () => make('DUP-1'),
      throwsA(isA<ProductValidationException>()),
    );
  });
}

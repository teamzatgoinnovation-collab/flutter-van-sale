import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/customer/repositories/customer_repository.dart';
import 'package:van_sale/customer/validation/customer_validators.dart';
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
    await db.delete('sync_logs');
    await db.delete('customers');
    await db.delete('products');
  });

  test('updateLocal enqueues update when customer already has erp_name', () async {
    final repo = CustomerRepository(VanSaleDb.instance);
    final created = await repo.createLocal(
      CustomerDraft()
        ..customerName = 'Acme'
        ..customerGroup = 'Commercial'
        ..territory = 'Saudi Arabia'
        ..mobileNo = '0501112233'
        ..addressLine1 = 'St 1'
        ..city = 'Riyadh'
        ..country = 'Saudi Arabia',
    );
    await VanSaleDb.instance.setCustomerSync(
      id: created.id,
      status: SyncStatus.uploaded,
      erpName: 'CUST-001',
      erpModified: '2026-01-01 10:00:00.000000',
    );
    await VanSaleDb.instance.clearQueueForEntity('customer', created.id);

    final draft = CustomerDraft()
      ..customerName = 'Acme Updated'
      ..customerGroup = 'Commercial'
      ..territory = 'Saudi Arabia'
      ..mobileNo = '0501112233'
      ..addressLine1 = 'St 2'
      ..city = 'Riyadh'
      ..country = 'Saudi Arabia';
    final updated = await repo.updateLocal(created.id, draft);
    expect(updated.syncStatus, SyncStatus.pending);

    final queue = await VanSaleDb.instance.peekQueue();
    final item = queue.firstWhere((q) => q.entityType == 'customer');
    expect(item.op, 'update');
  });

  test('deleteLocal for unsynced customer removes row', () async {
    final repo = CustomerRepository(VanSaleDb.instance);
    final created = await repo.createLocal(
      CustomerDraft()
        ..customerName = 'Temp'
        ..customerGroup = 'Commercial'
        ..territory = 'Saudi Arabia'
        ..mobileNo = '0502223344'
        ..addressLine1 = 'St 1'
        ..city = 'Jeddah'
        ..country = 'Saudi Arabia',
    );
    await repo.deleteLocal(created.id);
    expect(await repo.get(created.id), isNull);
    final queue = await VanSaleDb.instance.peekQueue();
    expect(queue.where((q) => q.entityId == created.id), isEmpty);
  });

  test('product updateLocal enqueues update with images preserved', () async {
    final repo = ProductRepository(VanSaleDb.instance);
    final created = await repo.createLocal(
      ProductDraft()
        ..itemCode = 'SKU-1'
        ..itemName = 'Widget'
        ..itemGroup = 'Products'
        ..stockUom = 'Nos'
        ..sellingRate = 10
        ..imagePath = '/tmp/a.jpg',
    );
    await VanSaleDb.instance.setProductSync(
      id: created.id,
      status: SyncStatus.uploaded,
      erpName: 'SKU-1',
      erpModified: '2026-01-01 10:00:00.000000',
    );
    await VanSaleDb.instance.clearQueueForEntity('product', created.id);

    final updated = await repo.updateLocal(
      created.id,
      ProductDraft()
        ..itemCode = 'SKU-1'
        ..itemName = 'Widget Plus'
        ..itemGroup = 'Products'
        ..stockUom = 'Nos'
        ..sellingRate = 12,
    );
    expect(updated.imagePath, '/tmp/a.jpg');
    final queue = await VanSaleDb.instance.peekQueue();
    expect(queue.firstWhere((q) => q.entityType == 'product').op, 'update');
  });

  test('sync log + conflict status helpers', () async {
    final db = VanSaleDb.instance;
    await db.addSyncLog(level: 'info', message: 'hello');
    final logs = await db.listSyncLogs(limit: 5);
    expect(logs.any((r) => '${r['message']}' == 'hello'), isTrue);

    await db.enqueue(
      clientId: 'c1',
      entityType: 'customer',
      entityId: 'x',
      op: 'update',
      method: 'm',
      args: const {},
    );
    final q = await db.peekQueue();
    await db.markQueueConflict(q.first.id, 'newer on server');
    final conflicted = await db.listQueueByStatuses(const ['conflict']);
    expect(conflicted, isNotEmpty);
  });
}

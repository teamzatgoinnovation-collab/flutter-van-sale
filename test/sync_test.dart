import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/customer/repositories/customer_repository.dart';
import 'package:van_sale/customer/validation/customer_validators.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/models/models.dart';
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

  test('corrupted queue entry is quarantined, not fatal to the batch', () async {
    final db = VanSaleDb.instance;
    final database = await db.database;

    await db.enqueue(
      clientId: 'good-1',
      entityType: 'customer',
      entityId: 'good-entity-1',
      op: 'update',
      method: 'm',
      args: const {'a': 1},
    );
    await db.enqueue(
      clientId: 'good-2',
      entityType: 'product',
      entityId: 'good-entity-2',
      op: 'update',
      method: 'm',
      args: const {'b': 2},
    );
    // Simulate a row corrupted by an interrupted write — enqueue() always
    // writes valid JSON, so insert the bad row directly.
    await database.insert('sync_queue', {
      'id': 'sq_corrupt_1',
      'client_id': 'corrupt-1',
      'entity_type': 'customer',
      'entity_id': 'corrupt-entity',
      'op': 'update',
      'method': 'm',
      'args_json': '{not valid json',
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Must not throw, and must still return the two good rows.
    final pending = await db.listQueueByStatuses(const ['pending']);
    expect(pending.length, 2);
    expect(pending.map((e) => e.clientId), containsAll(['good-1', 'good-2']));

    // The corrupted row is quarantined as failed, not left stuck pending.
    final rows = await database.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: ['sq_corrupt_1'],
    );
    expect(rows.single['status'], 'failed');
    expect(rows.single['last_error'], contains('Corrupted'));
  });

  test('failed items are not auto-claimed until their backoff window elapses', () async {
    final db = VanSaleDb.instance;
    final database = await db.database;

    // A failed item still backing off (due 10 minutes from now).
    await database.insert('sync_queue', {
      'id': 'sq_backing_off',
      'client_id': 'backing-off-1',
      'entity_type': 'customer',
      'entity_id': 'backing-off-entity',
      'op': 'update',
      'method': 'm',
      'args_json': '{"a":1}',
      'status': 'failed',
      'attempts': 1,
      'last_error': 'transient 500',
      'next_retry_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
    // A plain pending item, ready to go.
    await db.enqueue(
      clientId: 'ready-1',
      entityType: 'product',
      entityId: 'ready-entity',
      op: 'update',
      method: 'm',
      args: const {'b': 2},
    );

    // claimNext must skip the still-backing-off row and claim the pending one.
    final claimed = await db.claimNext();
    expect(claimed?.clientId, 'ready-1');

    // The backing-off row must remain untouched (still 'failed', not deleted).
    final stillFailed = await database.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: ['sq_backing_off'],
    );
    expect(stillFailed.single['status'], 'failed');

    // Once its backoff window has elapsed, it becomes claimable again.
    await database.update(
      'sync_queue',
      {'next_retry_at': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String()},
      where: 'id = ?',
      whereArgs: ['sq_backing_off'],
    );
    final claimedAfterBackoff = await db.claimNext();
    expect(claimedAfterBackoff?.clientId, 'backing-off-1');
    expect(claimedAfterBackoff?.status, 'uploading');
    expect(claimedAfterBackoff?.attempts, 2);
  });

  test('markQueueFailed schedules increasing backoff and never deletes the item', () async {
    final db = VanSaleDb.instance;
    final database = await db.database;

    await db.enqueue(
      clientId: 'retry-schedule-1',
      entityType: 'customer',
      entityId: 'retry-schedule-entity',
      op: 'update',
      method: 'm',
      args: const {'a': 1},
    );
    final queued = await db.peekQueue(statuses: const ['pending']);
    final id = queued.single.id;

    // Attempt 1 -> ~1 minute.
    final before1 = DateTime.now();
    await db.markQueueFailed(id, 'boom', attempts: 1);
    var row = (await database.query('sync_queue', where: 'id = ?', whereArgs: [id])).single;
    expect(row['status'], 'failed');
    var nextRetry = DateTime.parse(row['next_retry_at'] as String);
    expect(nextRetry.isAfter(before1.add(const Duration(seconds: 50))), isTrue);
    expect(nextRetry.isBefore(before1.add(const Duration(minutes: 2))), isTrue);

    // Attempt 4 -> capped at 2 hours, not unbounded.
    final before4 = DateTime.now();
    await db.markQueueFailed(id, 'boom again', attempts: 4);
    row = (await database.query('sync_queue', where: 'id = ?', whereArgs: [id])).single;
    nextRetry = DateTime.parse(row['next_retry_at'] as String);
    expect(nextRetry.isAfter(before4.add(const Duration(hours: 1, minutes: 55))), isTrue);
    expect(nextRetry.isBefore(before4.add(const Duration(hours: 2, minutes: 5))), isTrue);

    // Attempt 10 (way beyond schedule) -> still capped at 2 hours, never gives up.
    final before10 = DateTime.now();
    await db.markQueueFailed(id, 'boom yet again', attempts: 10);
    row = (await database.query('sync_queue', where: 'id = ?', whereArgs: [id])).single;
    expect(row['status'], 'failed');
    nextRetry = DateTime.parse(row['next_retry_at'] as String);
    expect(nextRetry.isBefore(before10.add(const Duration(hours: 2, minutes: 5))), isTrue);
  });

  test('corrupted queue rows never get auto-retried by claimNext', () async {
    final db = VanSaleDb.instance;
    final database = await db.database;

    await database.insert('sync_queue', {
      'id': 'sq_corrupt_auto',
      'client_id': 'corrupt-auto-1',
      'entity_type': 'customer',
      'entity_id': 'corrupt-auto-entity',
      'op': 'update',
      'method': 'm',
      'args_json': '{still not valid',
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'created_at': DateTime.now().toIso8601String(),
    });

    // First claim attempt quarantines it and finds nothing else to claim.
    final firstClaim = await db.claimNext();
    expect(firstClaim, isNull);
    final quarantined = (await database.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: ['sq_corrupt_auto'],
    )).single;
    expect(quarantined['status'], 'failed');
    final nextRetryAt = DateTime.parse(quarantined['next_retry_at'] as String);
    expect(nextRetryAt.isAfter(DateTime.now().add(const Duration(days: 300))), isTrue);

    // A subsequent background claim must not spin on it again.
    final secondClaim = await db.claimNext();
    expect(secondClaim, isNull);
  });
}

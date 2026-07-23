import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/data/van_sale_repo.dart';
import 'package:van_sale/models/models.dart';
import 'package:van_sale/pages/settings_page.dart';
import 'package:van_sale/services/prefs.dart';
import 'package:van_sale/services/session.dart';
import 'package:van_sale/services/sync_service.dart';
import 'package:van_sale/services/van_sale_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await VanSalePrefs.instance.resetForTest();
    final prefs = VanSalePrefs.instance;
    await prefs.setWorkMode(VanSaleWorkMode.online);
    await prefs.setAllowNegativeStock(false);
    await prefs.setBackgroundSync(true);
    await prefs.setAutoSyncAfterWrite(false);
    await prefs.setLowStockThreshold(5);
    final db = await VanSaleDb.instance.database;
    await db.delete('sync_queue');
    await db.delete('van_orders');
    await db.delete('van_stock');
    await db.delete('sync_logs');
  });

  test('prefs defaults: online mode, negative stock off', () {
    expect(VanSalePrefs.instance.workMode, VanSaleWorkMode.online);
    expect(VanSalePrefs.instance.allowNegativeStock, isFalse);
    expect(VanSalePrefs.instance.backgroundSync, isTrue);
    expect(VanSalePrefs.instance.autoSyncAfterWrite, isFalse);
    expect(VanSalePrefs.instance.lowStockThreshold, 5);
  });

  test('prefs round-trip work mode and stock policy', () async {
    final prefs = VanSalePrefs.instance;
    await prefs.setWorkMode(VanSaleWorkMode.offline);
    await prefs.setAllowNegativeStock(true);
    await prefs.setBackgroundSync(false);
    await prefs.setAutoSyncAfterWrite(true);
    await prefs.setLowStockThreshold(3);
    expect(prefs.workMode, VanSaleWorkMode.offline);
    expect(prefs.allowNegativeStock, isTrue);
    expect(prefs.backgroundSync, isFalse);
    expect(prefs.autoSyncAfterWrite, isTrue);
    expect(prefs.lowStockThreshold, 3);
    expect(VanSalePolicy.instance.syncAllowed, isFalse);
  });

  test('online mode gate fails when not signed in', () async {
    await VanSalePrefs.instance.setWorkMode(VanSaleWorkMode.online);
    expect(
      () => VanSalePolicy.instance.assertCanMutate(null),
      throwsStateError,
    );
    expect(
      () => VanSalePolicy.instance.assertCanMutate(VanSaleSession()),
      throwsStateError,
    );
  });

  test('createOrder blocks insufficient stock unless allow negative', () async {
    await VanSalePrefs.instance.setWorkMode(VanSaleWorkMode.onlineOffline);
    await VanSalePrefs.instance.setAllowNegativeStock(false);
    await VanSalePrefs.instance.setWarehouse('Van-01');
    await VanSaleDb.instance.replaceStock(const [
      StockLine(
        itemCode: 'SKU-A',
        itemName: 'Item A',
        qty: 1,
        uom: 'Nos',
        unitPrice: 2,
      ),
    ]);
    await expectLater(
      vanSaleRepo.createOrder(
        customerName: 'Cust',
        lines: const [
          OrderLine(
            itemCode: 'SKU-A',
            itemName: 'Item A',
            qty: 5,
            unitPrice: 2,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    await VanSalePrefs.instance.setAllowNegativeStock(true);
    final order = await vanSaleRepo.createOrder(
      customerName: 'Cust',
      lines: const [
        OrderLine(
          itemCode: 'SKU-A',
          itemName: 'Item A',
          qty: 5,
          unitPrice: 2,
        ),
      ],
    );
    expect(order.amount, 10);
    final stock = await vanSaleRepo.getStock('SKU-A');
    expect(stock!.qty, -4);
  });

  test('offline mode flush returns empty', () async {
    await VanSalePrefs.instance.setWorkMode(VanSaleWorkMode.offline);
    final sync = SyncService(VanSaleSession());
    final result = await sync.flush(mode: SyncMode.manual);
    expect(result.uploaded, 0);
    expect(result.failed, 0);
  });

  test('shouldAttemptFlushAfterWrite matrix for online/offline/hybrid', () async {
    final prefs = VanSalePrefs.instance;
    final policy = VanSalePolicy.instance;

    await prefs.setWorkMode(VanSaleWorkMode.online);
    await prefs.setAutoSyncAfterWrite(false);
    expect(policy.syncAllowed, isTrue);
    expect(policy.shouldAttemptFlushAfterWrite, isTrue);
    expect(policy.backgroundSyncDesired, isTrue);

    await prefs.setWorkMode(VanSaleWorkMode.offline);
    await prefs.setAutoSyncAfterWrite(true);
    await prefs.setBackgroundSync(true);
    expect(policy.syncAllowed, isFalse);
    expect(policy.shouldAttemptFlushAfterWrite, isFalse);
    expect(policy.backgroundSyncDesired, isFalse);

    await prefs.setWorkMode(VanSaleWorkMode.onlineOffline);
    await prefs.setAutoSyncAfterWrite(false);
    await prefs.setBackgroundSync(true);
    expect(policy.syncAllowed, isTrue);
    expect(policy.shouldAttemptFlushAfterWrite, isFalse);
    expect(policy.backgroundSyncDesired, isTrue);

    await prefs.setAutoSyncAfterWrite(true);
    expect(policy.shouldAttemptFlushAfterWrite, isTrue);

    await prefs.setBackgroundSync(false);
    expect(policy.backgroundSyncDesired, isFalse);
  });

  test('offline and hybrid allow mutate without session', () async {
    await VanSalePrefs.instance.setWorkMode(VanSaleWorkMode.offline);
    await VanSalePolicy.instance.assertCanMutate(null);

    await VanSalePrefs.instance.setWorkMode(VanSaleWorkMode.onlineOffline);
    await VanSalePolicy.instance.assertCanMutate(null);
  });

  testWidgets('SettingsPage shows work mode and negative stock', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          session: VanSaleSession(),
          sync: SyncService(VanSaleSession()),
        ),
      ),
    );
    expect(find.text('Work mode'), findsOneWidget);
    expect(find.text('Stock policy'), findsOneWidget);
    expect(find.text('Allow negative stock'), findsOneWidget);
    expect(find.text('Low-stock threshold'), findsOneWidget);
  });
}

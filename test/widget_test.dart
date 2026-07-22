import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/data/van_sale_repo.dart';
import 'package:van_sale/models/models.dart';
import 'package:van_sale/services/prefs.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await VanSalePrefs.instance.init();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('createOrder persists entity + outbox with same client_id', () async {
    final db = VanSaleDb.instance;
    final database = await db.database;
    await database.delete('sync_queue');
    await database.delete('van_orders');
    await database.delete('collections');
    await database.delete('van_stock');
    await database.delete('route_stops');
    await database.delete('meta');

    await db.replaceStock(const [
      StockLine(
        itemCode: 'SKU-WATER-1.5',
        itemName: 'Water 1.5L',
        qty: 48,
        uom: 'Nos',
        unitPrice: 2.5,
      ),
    ]);

    final repo = VanSaleRepo(db);
    await repo.init();
    await VanSalePrefs.instance.setWorkMode(VanSaleWorkMode.onlineOffline);

    final order = await repo.createOrder(
      customerName: 'City Grocer',
      lines: const [
        OrderLine(
          itemCode: 'SKU-WATER-1.5',
          itemName: 'Water 1.5L',
          qty: 2,
          unitPrice: 2.5,
        ),
      ],
    );

    final orders = await repo.listOrders();
    expect(orders.length, 1);
    expect(orders.first.clientId, order.clientId);
    expect(orders.first.syncStatus, SyncStatus.pending);

    final queue = await db.peekQueue(statuses: const ['pending']);
    expect(queue.length, greaterThanOrEqualTo(1));
    final create = queue.firstWhere((q) => q.entityType == 'van_order');
    expect(create.clientId, order.clientId);
    expect(create.args['client_id'], order.clientId);

    await db.enqueue(
      clientId: order.clientId,
      entityType: 'van_order',
      entityId: order.id,
      op: 'create',
      method: 'zatgo_core.api.v1.go_van.orders.create',
      args: {'client_id': order.clientId},
    );
    final again = await db.peekQueue(statuses: const ['pending']);
    final creates = again.where(
      (q) => q.entityType == 'van_order' && q.op == 'create',
    );
    expect(creates.length, 1);
  });
}

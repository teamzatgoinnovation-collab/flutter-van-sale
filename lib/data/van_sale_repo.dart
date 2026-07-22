import 'package:sqflite/sqflite.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import '../models/models.dart';
import '../services/session.dart';
import 'van_sale_db.dart';

/// Local-first VanSale repository. All reads/writes go through SQLite.
class VanSaleRepo {
  VanSaleRepo(this.db);

  final VanSaleDb db;

  String routeName = 'VanSale route';
  String driverName = 'Driver';

  Future<void> init() async {
    await db.seedIfNeeded();
    routeName = await db.metaGet('route_name') ?? routeName;
    driverName = await db.metaGet('driver_name') ?? driverName;
    await db.requeueInFlightAsQueued();
  }

  Future<List<RouteStop>> listStops() => db.listStops();

  Future<List<VanOrder>> listOrders({String query = ''}) =>
      db.listOrders(query: query);

  Future<List<Collection>> listCollections() => db.listCollections();

  Future<List<StockLine>> listStock() => db.listStock();

  Future<DaySummary> summary() => db.summary();

  Future<Map<String, int>> syncCounts() => db.syncCounts();

  /// Pull trips when connected; never wipe commercial docs. Seed stays if empty.
  Future<void> refreshFromErpnext(VanSaleSession session) async {
    if (!session.connected) return;
    try {
      await session.store.callMethod(ZatGoApiMethods.goVanPing);
      final env = await session.store.callMethod(
        ZatGoApiMethods.goVanTripsList,
        args: {'page': 1, 'page_size': 100},
      );
      final rows = env.data is List ? env.data as List : const [];
      if (rows.isEmpty) return;

      for (var i = 0; i < rows.length; i++) {
        final map = Map<String, dynamic>.from(rows[i] as Map);
        final id = '${map['name'] ?? map['id'] ?? 'trip-$i'}';
        final existing = await db.visitStatusOf(id);
        await db.upsertStop(
          RouteStop(
            id: id,
            customerName: '${map['customer'] ?? map['title'] ?? 'Stop ${i + 1}'}',
            address: '${map['address'] ?? ''}',
            sequence: i + 1,
            lat: double.tryParse('${map['lat'] ?? ''}') ?? 0,
            lng: double.tryParse('${map['lng'] ?? ''}') ?? 0,
            plannedAt: DateTime.now(),
            visitStatus: existing ?? VisitStatus.planned,
          ),
        );
      }
      await db.metaSet('last_pull_at', DateTime.now().toIso8601String());
    } catch (_) {
      // Keep local SQLite state on pull failure.
    }
  }

  Future<VanOrder> createOrder({
    required String customerName,
    required List<OrderLine> lines,
  }) async {
    if (lines.isEmpty) {
      throw StateError('Order needs at least one stock line.');
    }
    final amount = lines.fold<double>(0, (s, l) => s + l.amount);
    final clientId = newClientId();
    final id = newLocalId('ord');
    final order = VanOrder(
      id: id,
      clientId: clientId,
      customerName: customerName,
      lines: lines,
      amount: amount,
      createdAt: DateTime.now(),
      syncStatus: SyncStatus.queued,
    );

    final database = await db.database;
    await database.transaction((txn) async {
      for (final line in lines) {
        final stock = await db.getStock(line.itemCode, executor: txn);
        if (stock == null) {
          throw StateError('Unknown item ${line.itemCode}');
        }
        if (stock.qty < line.qty) {
          throw StateError(
            'Insufficient stock for ${stock.itemName} '
            '(have ${stock.qty}, need ${line.qty})',
          );
        }
        await db.setStockQty(
          line.itemCode,
          stock.qty - line.qty,
          executor: txn,
        );
      }
      await db.insertOrder(order, executor: txn);
      await db.enqueue(
        clientId: clientId,
        entityType: 'van_order',
        entityId: id,
        op: 'create',
        method: 'zatgo_core.api.v1.go_van.orders.create',
        args: {
          'client_id': clientId,
          'customer_name': customerName,
          'items': [for (final l in lines) l.toJson()],
          'amount': amount,
        },
        executor: txn,
      );
    });
    return order;
  }

  Future<Collection> recordCollection({
    required String customerName,
    required double amount,
    required String method,
  }) async {
    if (amount <= 0) throw StateError('Collection amount must be positive.');
    final clientId = newClientId();
    final id = newLocalId('col');
    final row = Collection(
      id: id,
      clientId: clientId,
      customerName: customerName,
      amount: amount,
      method: method,
      collectedAt: DateTime.now(),
      syncStatus: SyncStatus.queued,
    );

    final database = await db.database;
    await database.transaction((txn) async {
      await db.insertCollection(row, executor: txn);
      await db.enqueue(
        clientId: clientId,
        entityType: 'collection',
        entityId: id,
        op: 'create',
        method: 'zatgo_core.api.v1.go_van.collections.create',
        args: {
          'client_id': clientId,
          'customer_name': customerName,
          'amount': amount,
          'method': method,
        },
        executor: txn,
      );
    });
    return row;
  }

  Future<RouteStop?> updateVisit(String id, VisitStatus status) async {
    final stops = await db.listStops();
    final current = stops.where((s) => s.id == id).firstOrNull;
    if (current == null) return null;

    final clientId = 'visit_$id';
    final database = await db.database;
    await database.transaction((txn) async {
      await txn.update(
        'route_stops',
        {
          'visit_status': status.name,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.enqueue(
        clientId: clientId,
        entityType: 'route_stop',
        entityId: id,
        op: 'update',
        method: 'zatgo_core.api.v1.go_van.visits.update',
        args: {
          'client_id': clientId,
          'stop_id': id,
          'visit_status': status.name,
        },
        executor: txn,
        conflict: ConflictAlgorithm.replace,
      );
    });
    return current.copyWith(visitStatus: status);
  }

  Future<void> adjustStock({
    required String itemCode,
    required double delta,
  }) async {
    final database = await db.database;
    await database.transaction((txn) async {
      final stock = await db.getStock(itemCode, executor: txn);
      if (stock == null) throw StateError('Unknown item $itemCode');
      final next = stock.qty + delta;
      if (next < 0) {
        throw StateError('Stock cannot go negative for ${stock.itemName}');
      }
      await db.setStockQty(itemCode, next, executor: txn);
      final clientId = newClientId();
      // Unique entity_id per adjust so retries never collide with prior adjusts.
      await db.enqueue(
        clientId: clientId,
        entityType: 'van_stock',
        entityId: clientId,
        op: 'update',
        method: 'zatgo_core.api.v1.go_van.stock.adjust',
        args: {
          'client_id': clientId,
          'item_code': itemCode,
          'delta': delta,
          'qty_after': next,
        },
        executor: txn,
      );
    });
  }
}

final vanSaleRepo = VanSaleRepo(VanSaleDb.instance);

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:uuid/uuid.dart';

import '../models/models.dart';

const _uuid = Uuid();

String newClientId() => _uuid.v4();

String newLocalId(String prefix) =>
    '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}';

Future<void> initVanSaleSqflite() async {
  if (kIsWeb) {
    throw UnsupportedError('VanSale SQLite is not supported on web.');
  }
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

class VanSaleDb {
  VanSaleDb._();
  static final VanSaleDb instance = VanSaleDb._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'van_sale.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE route_stops (
  id TEXT PRIMARY KEY NOT NULL,
  customer_name TEXT NOT NULL,
  address TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  visit_status TEXT NOT NULL,
  planned_at TEXT,
  updated_at TEXT NOT NULL
)''');
        await db.execute('''
CREATE TABLE van_orders (
  id TEXT PRIMARY KEY NOT NULL,
  client_id TEXT NOT NULL UNIQUE,
  customer_name TEXT NOT NULL,
  items_json TEXT NOT NULL,
  amount REAL NOT NULL,
  sync_status TEXT NOT NULL,
  erp_name TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''');
        await db.execute('''
CREATE TABLE collections (
  id TEXT PRIMARY KEY NOT NULL,
  client_id TEXT NOT NULL UNIQUE,
  customer_name TEXT NOT NULL,
  amount REAL NOT NULL,
  method TEXT NOT NULL,
  sync_status TEXT NOT NULL,
  erp_name TEXT,
  collected_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''');
        await db.execute('''
CREATE TABLE van_stock (
  item_code TEXT PRIMARY KEY NOT NULL,
  item_name TEXT NOT NULL,
  qty REAL NOT NULL,
  uom TEXT NOT NULL,
  unit_price REAL NOT NULL,
  updated_at TEXT NOT NULL
)''');
        await db.execute('''
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY NOT NULL,
  client_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL,
  method TEXT NOT NULL,
  args_json TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(entity_type, entity_id, op)
)''');
        await db.execute('''
CREATE TABLE meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)''');
      },
    );
  }

  Future<String?> metaGet(String key) async {
    final db = await database;
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return '${rows.first['value']}';
  }

  Future<void> metaSet(String key, String value) async {
    final db = await database;
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isSeeded() async => (await metaGet('seeded')) == '1';

  Future<void> seedIfNeeded() async {
    if (await isSeeded()) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final stops = [
        (
          'stop-1',
          'City Grocer',
          '12 King Fahd Rd',
          1,
          24.7136,
          46.6753,
        ),
        (
          'stop-2',
          'Fresh Basket Co-op',
          '88 Olaya St',
          2,
          24.6900,
          46.6850,
        ),
        (
          'stop-3',
          'Corner Mart',
          '4 Tahlia St',
          3,
          24.7005,
          46.6920,
        ),
        (
          'stop-4',
          'Sunrise Cafe',
          '21 Prince Sultan Rd',
          4,
          24.7201,
          46.6602,
        ),
        (
          'stop-5',
          'Neighborhood Mini',
          '9 Exit 5 service rd',
          5,
          24.7350,
          46.7100,
        ),
      ];
      for (final s in stops) {
        await txn.insert('route_stops', {
          'id': s.$1,
          'customer_name': s.$2,
          'address': s.$3,
          'sequence': s.$4,
          'lat': s.$5,
          'lng': s.$6,
          'visit_status': VisitStatus.planned.name,
          'planned_at': now,
          'updated_at': now,
        });
      }

      final stock = [
        ('SKU-WATER-1.5', 'Water 1.5L', 48.0, 'Nos', 2.5),
        ('SKU-JUICE-OR', 'Orange Juice 1L', 24.0, 'Nos', 6.0),
        ('SKU-MILK-1', 'Fresh Milk 1L', 30.0, 'Nos', 5.5),
        ('SKU-BREAD', 'Sandwich Bread', 20.0, 'Nos', 4.0),
        ('SKU-CHIPS', 'Chips Family', 36.0, 'Nos', 3.5),
        ('SKU-YOG', 'Yogurt Cup', 40.0, 'Nos', 2.0),
        ('SKU-SOAP', 'Dish Soap 750ml', 18.0, 'Nos', 8.0),
      ];
      for (final line in stock) {
        await txn.insert('van_stock', {
          'item_code': line.$1,
          'item_name': line.$2,
          'qty': line.$3,
          'uom': line.$4,
          'unit_price': line.$5,
          'updated_at': now,
        });
      }

      await txn.insert('meta', {'key': 'seeded', 'value': '1'});
      await txn.insert('meta', {
        'key': 'route_name',
        'value': 'Riyadh North · VanSale',
      });
      await txn.insert('meta', {'key': 'driver_name', 'value': 'Driver'});
    });
  }

  // --- stops ---

  Future<List<RouteStop>> listStops() async {
    final db = await database;
    final rows = await db.query('route_stops', orderBy: 'sequence ASC');
    return rows.map(_stopFromRow).toList(growable: false);
  }

  Future<void> upsertStop(RouteStop stop, {DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'route_stops',
      {
        'id': stop.id,
        'customer_name': stop.customerName,
        'address': stop.address,
        'sequence': stop.sequence,
        'lat': stop.lat,
        'lng': stop.lng,
        'visit_status': stop.visitStatus.name,
        'planned_at': stop.plannedAt?.toIso8601String(),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateVisitStatus(String id, VisitStatus status) async {
    final db = await database;
    await db.update(
      'route_stops',
      {
        'visit_status': status.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<VisitStatus?> visitStatusOf(String id) async {
    final db = await database;
    final rows = await db.query(
      'route_stops',
      columns: ['visit_status'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return VisitStatus.values.byName('${rows.first['visit_status']}');
  }

  // --- stock ---

  Future<List<StockLine>> listStock() async {
    final db = await database;
    final rows = await db.query('van_stock', orderBy: 'item_name ASC');
    return [
      for (final r in rows)
        StockLine(
          itemCode: '${r['item_code']}',
          itemName: '${r['item_name']}',
          qty: (r['qty'] as num).toDouble(),
          uom: '${r['uom']}',
          unitPrice: (r['unit_price'] as num).toDouble(),
        ),
    ];
  }

  Future<StockLine?> getStock(String itemCode, {DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    final rows = await db.query(
      'van_stock',
      where: 'item_code = ?',
      whereArgs: [itemCode],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return StockLine(
      itemCode: '${r['item_code']}',
      itemName: '${r['item_name']}',
      qty: (r['qty'] as num).toDouble(),
      uom: '${r['uom']}',
      unitPrice: (r['unit_price'] as num).toDouble(),
    );
  }

  Future<void> setStockQty(
    String itemCode,
    double qty, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.update(
      'van_stock',
      {
        'qty': qty,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'item_code = ?',
      whereArgs: [itemCode],
    );
  }

  // --- orders ---

  Future<List<VanOrder>> listOrders({String query = ''}) async {
    final db = await database;
    final rows = await db.query('van_orders', orderBy: 'created_at DESC');
    final all = rows.map(_orderFromRow).toList();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where(
          (o) =>
              o.customerName.toLowerCase().contains(q) ||
              o.id.toLowerCase().contains(q) ||
              o.clientId.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  Future<void> insertOrder(VanOrder order, {DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('van_orders', {
      'id': order.id,
      'client_id': order.clientId,
      'customer_name': order.customerName,
      'items_json': jsonEncode([for (final l in order.lines) l.toJson()]),
      'amount': order.amount,
      'sync_status': order.syncStatus.name,
      'erp_name': order.erpName,
      'created_at': order.createdAt.toIso8601String(),
      'updated_at': now,
    });
  }

  Future<void> setOrderSync({
    required String id,
    required SyncStatus status,
    String? erpName,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.update(
      'van_orders',
      {
        'sync_status': status.name,
        'erp_name': ?erpName,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- collections ---

  Future<List<Collection>> listCollections() async {
    final db = await database;
    final rows = await db.query('collections', orderBy: 'collected_at DESC');
    return rows.map(_collectionFromRow).toList(growable: false);
  }

  Future<void> insertCollection(
    Collection c, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('collections', {
      'id': c.id,
      'client_id': c.clientId,
      'customer_name': c.customerName,
      'amount': c.amount,
      'method': c.method,
      'sync_status': c.syncStatus.name,
      'erp_name': c.erpName,
      'collected_at': c.collectedAt.toIso8601String(),
      'updated_at': now,
    });
  }

  Future<void> setCollectionSync({
    required String id,
    required SyncStatus status,
    String? erpName,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.update(
      'collections',
      {
        'sync_status': status.name,
        'erp_name': ?erpName,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- sync queue ---

  Future<void> enqueue({
    required String clientId,
    required String entityType,
    required String entityId,
    required String op,
    required String method,
    required Map<String, dynamic> args,
    DatabaseExecutor? executor,
    ConflictAlgorithm conflict = ConflictAlgorithm.ignore,
  }) async {
    final db = executor ?? await database;
    // Stable primary key for (entity, op) so create is idempotent / visit replaceable.
    final id = 'sq_${entityType}_${entityId}_$op';
    await db.insert(
      'sync_queue',
      {
        'id': id,
        'client_id': clientId,
        'entity_type': entityType,
        'entity_id': entityId,
        'op': op,
        'method': method,
        'args_json': jsonEncode(args),
        'status': 'queued',
        'attempts': 0,
        'last_error': null,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: conflict,
    );
  }

  Future<List<SyncQueueItem>> peekQueue({
    List<String> statuses = const ['queued', 'awaiting_erp'],
  }) async {
    final db = await database;
    final placeholders = List.filled(statuses.length, '?').join(',');
    final rows = await db.query(
      'sync_queue',
      where: 'status IN ($placeholders)',
      whereArgs: statuses,
      orderBy: 'created_at ASC',
    );
    return rows.map(_queueFromRow).toList(growable: false);
  }

  Future<SyncQueueItem?> claimNext() async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'sync_queue',
        where: "status = 'queued'",
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final item = _queueFromRow(rows.first);
      await txn.update(
        'sync_queue',
        {
          'status': 'in_flight',
          'attempts': item.attempts + 1,
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );
      return SyncQueueItem(
        id: item.id,
        clientId: item.clientId,
        entityType: item.entityType,
        entityId: item.entityId,
        op: item.op,
        method: item.method,
        args: item.args,
        status: 'in_flight',
        attempts: item.attempts + 1,
        createdAt: item.createdAt,
        lastError: item.lastError,
      );
    });
  }

  Future<void> markQueueDone(String id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markQueueAwaitingErp(String id, {String? error}) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'awaiting_erp',
        'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markQueueFailed(String id, String error) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'failed',
        'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> requeueFailed(String id) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'queued',
        'last_error': null,
      },
      where: 'id = ? AND status = ?',
      whereArgs: [id, 'failed'],
    );
  }

  Future<void> requeueInFlightAsQueued() async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 'queued'},
      where: 'status = ?',
      whereArgs: ['in_flight'],
    );
  }

  Future<Map<String, int>> syncCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS c FROM sync_queue GROUP BY status',
    );
    final out = <String, int>{
      'queued': 0,
      'in_flight': 0,
      'awaiting_erp': 0,
      'failed': 0,
    };
    for (final r in rows) {
      out['${r['status']}'] = (r['c'] as num).toInt();
    }
    return out;
  }

  Future<DaySummary> summary() async {
    final stops = await listStops();
    final orders = await listOrders();
    final collections = await listCollections();
    final stock = await listStock();
    final counts = await syncCounts();
    final done = stops
        .where((s) => s.visitStatus == VisitStatus.completed)
        .length;
    final queuedOrders = orders
        .where((o) => o.syncStatus != SyncStatus.synced)
        .length;
    final collected = collections.fold<double>(0, (s, c) => s + c.amount);
    return DaySummary(
      stopsTotal: stops.length,
      stopsDone: done,
      ordersQueued: queuedOrders,
      collectionsToday: collected,
      vanStockSku: stock.length,
      syncQueued: counts['queued'] ?? 0,
      syncInFlight: counts['in_flight'] ?? 0,
      syncAwaitingErp: counts['awaiting_erp'] ?? 0,
      syncFailed: counts['failed'] ?? 0,
    );
  }

  RouteStop _stopFromRow(Map<String, Object?> r) {
    return RouteStop(
      id: '${r['id']}',
      customerName: '${r['customer_name']}',
      address: '${r['address']}',
      sequence: (r['sequence'] as num).toInt(),
      lat: (r['lat'] as num).toDouble(),
      lng: (r['lng'] as num).toDouble(),
      plannedAt: r['planned_at'] == null
          ? null
          : DateTime.tryParse('${r['planned_at']}'),
      visitStatus: VisitStatus.values.byName('${r['visit_status']}'),
    );
  }

  VanOrder _orderFromRow(Map<String, Object?> r) {
    final raw = jsonDecode('${r['items_json']}');
    final lines = <OrderLine>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          lines.add(OrderLine.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return VanOrder(
      id: '${r['id']}',
      clientId: '${r['client_id']}',
      customerName: '${r['customer_name']}',
      lines: lines,
      amount: (r['amount'] as num).toDouble(),
      createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
      syncStatus: _syncStatusFrom('${r['sync_status']}'),
      erpName: r['erp_name'] == null ? null : '${r['erp_name']}',
    );
  }

  Collection _collectionFromRow(Map<String, Object?> r) {
    return Collection(
      id: '${r['id']}',
      clientId: '${r['client_id']}',
      customerName: '${r['customer_name']}',
      amount: (r['amount'] as num).toDouble(),
      method: '${r['method']}',
      collectedAt:
          DateTime.tryParse('${r['collected_at']}') ?? DateTime.now(),
      syncStatus: _syncStatusFrom('${r['sync_status']}'),
      erpName: r['erp_name'] == null ? null : '${r['erp_name']}',
    );
  }

  SyncQueueItem _queueFromRow(Map<String, Object?> r) {
    final decoded = jsonDecode('${r['args_json']}');
    final args = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    return SyncQueueItem(
      id: '${r['id']}',
      clientId: '${r['client_id']}',
      entityType: '${r['entity_type']}',
      entityId: '${r['entity_id']}',
      op: '${r['op']}',
      method: '${r['method']}',
      args: args,
      status: '${r['status']}',
      attempts: (r['attempts'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
      lastError: r['last_error'] == null ? null : '${r['last_error']}',
    );
  }

  SyncStatus _syncStatusFrom(String raw) {
    return switch (raw) {
      'queued' => SyncStatus.queued,
      'inFlight' || 'in_flight' => SyncStatus.inFlight,
      'awaitingErp' || 'awaiting_erp' => SyncStatus.awaitingErp,
      'synced' => SyncStatus.synced,
      'failed' => SyncStatus.failed,
      _ => SyncStatus.queued,
    };
  }
}

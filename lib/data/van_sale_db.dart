import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../customer/models/customer_model.dart';

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
      version: 2,
      onCreate: (db, version) async {
        await _createV1(db);
        await _createCustomersTable(db);
        await _createCustomerIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createCustomersTable(db);
          await _createCustomerIndexes(db);
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_sync_queue_status_created '
            'ON sync_queue(status, created_at)',
          );
        }
      },
    );
  }

  Future<void> _createV1(Database db) async {
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status_created '
      'ON sync_queue(status, created_at)',
    );
  }

  Future<void> _createCustomersTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY NOT NULL,
  client_id TEXT NOT NULL UNIQUE,
  erp_name TEXT,
  sync_status TEXT NOT NULL,
  last_error TEXT,
  customer_name TEXT NOT NULL,
  customer_name_ar TEXT,
  customer_type TEXT NOT NULL,
  customer_group TEXT NOT NULL,
  territory TEXT NOT NULL,
  tax_id TEXT,
  cr_number TEXT,
  customer_code TEXT,
  website TEXT,
  industry TEXT,
  mobile_no TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address_line1 TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT NOT NULL,
  state TEXT,
  country TEXT NOT NULL,
  postal_code TEXT,
  google_map_url TEXT,
  latitude REAL,
  longitude REAL,
  price_list TEXT,
  sales_person TEXT,
  credit_limit REAL,
  payment_terms TEXT,
  currency TEXT,
  enabled INTEGER NOT NULL DEFAULT 1,
  remarks TEXT,
  cr_image_path TEXT,
  vat_certificate_path TEXT,
  customer_photo_path TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''');
  }

  Future<void> _createCustomerIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_sync ON customers(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(customer_name)',
    );
    // Partial uniqueness is enforced in repository (empty duplicates allowed).
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_mobile ON customers(mobile_no)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_tax ON customers(tax_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_cr ON customers(cr_number)',
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
    await db.insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> isSeeded() async => (await metaGet('seeded')) == '1';

  /// No Flutter seed data — ERPNext is the only source of truth.
  Future<void> seedIfNeeded() async {
    // Intentionally empty.
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
    await db.insert('route_stops', {
      'id': stop.id,
      'customer_name': stop.customerName,
      'address': stop.address,
      'sequence': stop.sequence,
      'lat': stop.lat,
      'lng': stop.lng,
      'visit_status': stop.visitStatus.name,
      'planned_at': stop.plannedAt?.toIso8601String(),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<StockLine?> getStock(
    String itemCode, {
    DatabaseExecutor? executor,
  }) async {
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
      {'qty': qty, 'updated_at': DateTime.now().toIso8601String()},
      where: 'item_code = ?',
      whereArgs: [itemCode],
    );
  }

  Future<void> replaceStock(List<StockLine> lines) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('van_stock');
      for (final line in lines) {
        await txn.insert('van_stock', {
          'item_code': line.itemCode,
          'item_name': line.itemName,
          'qty': line.qty,
          'uom': line.uom,
          'unit_price': line.unitPrice,
          'updated_at': now,
        });
      }
    });
  }

  Future<void> upsertStockLine(StockLine line) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('van_stock', {
      'item_code': line.itemCode,
      'item_name': line.itemName,
      'qty': line.qty,
      'uom': line.uom,
      'unit_price': line.unitPrice,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearStops() async {
    final db = await database;
    await db.delete('route_stops');
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

  // --- customers ---

  Future<void> upsertCustomer(CustomerModel c, {DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    await db.insert('customers', _customerToRow(c), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<CustomerModel?> getCustomer(String id) async {
    final db = await database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _customerFromRow(rows.first);
  }

  Future<List<CustomerModel>> listCustomers({String? query, bool enabledOnly = true}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (enabledOnly) {
      where.add('enabled = 1');
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      where.add(
        '(customer_name LIKE ? OR customer_name_ar LIKE ? OR mobile_no LIKE ? OR erp_name LIKE ? OR tax_id LIKE ?)',
      );
      args.addAll([q, q, q, q, q]);
    }
    final rows = await db.query(
      'customers',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'customer_name COLLATE NOCASE ASC',
    );
    return rows.map(_customerFromRow).toList(growable: false);
  }

  Future<CustomerModel?> findCustomerDuplicate({
    String? mobileNo,
    String? taxId,
    String? crNumber,
    String? excludeId,
  }) async {
    final db = await database;
    if (mobileNo != null && mobileNo.trim().isNotEmpty) {
      final rows = await db.query(
        'customers',
        where: excludeId == null
            ? 'mobile_no = ?'
            : 'mobile_no = ? AND id != ?',
        whereArgs: excludeId == null
            ? [mobileNo.trim()]
            : [mobileNo.trim(), excludeId],
        limit: 1,
      );
      if (rows.isNotEmpty) return _customerFromRow(rows.first);
    }
    if (taxId != null && taxId.trim().isNotEmpty) {
      final rows = await db.query(
        'customers',
        where: excludeId == null ? 'tax_id = ?' : 'tax_id = ? AND id != ?',
        whereArgs: excludeId == null
            ? [taxId.trim()]
            : [taxId.trim(), excludeId],
        limit: 1,
      );
      if (rows.isNotEmpty) return _customerFromRow(rows.first);
    }
    if (crNumber != null && crNumber.trim().isNotEmpty) {
      final rows = await db.query(
        'customers',
        where: excludeId == null
            ? 'cr_number = ?'
            : 'cr_number = ? AND id != ?',
        whereArgs: excludeId == null
            ? [crNumber.trim()]
            : [crNumber.trim(), excludeId],
        limit: 1,
      );
      if (rows.isNotEmpty) return _customerFromRow(rows.first);
    }
    return null;
  }

  Future<void> setCustomerSync({
    required String id,
    required SyncStatus status,
    String? erpName,
    String? lastError,
  }) async {
    final db = await database;
    await db.update(
      'customers',
      {
        'sync_status': status.name,
        if (erpName != null) 'erp_name': erpName,
        'last_error': lastError,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Map<String, Object?> _customerToRow(CustomerModel c) => {
        'id': c.id,
        'client_id': c.clientId,
        'erp_name': c.erpName,
        'sync_status': c.syncStatus.name,
        'last_error': c.lastError,
        'customer_name': c.customerName,
        'customer_name_ar': c.customerNameAr,
        'customer_type': c.customerType,
        'customer_group': c.customerGroup,
        'territory': c.territory,
        'tax_id': c.taxId,
        'cr_number': c.crNumber,
        'customer_code': c.customerCode,
        'website': c.website,
        'industry': c.industry,
        'mobile_no': c.mobileNo,
        'phone': c.phone,
        'email': c.email,
        'address_line1': c.addressLine1,
        'address_line2': c.addressLine2,
        'city': c.city,
        'state': c.state,
        'country': c.country,
        'postal_code': c.postalCode,
        'google_map_url': c.googleMapUrl,
        'latitude': c.latitude,
        'longitude': c.longitude,
        'price_list': c.priceList,
        'sales_person': c.salesPerson,
        'credit_limit': c.creditLimit,
        'payment_terms': c.paymentTerms,
        'currency': c.currency,
        'enabled': c.enabled ? 1 : 0,
        'remarks': c.remarks,
        'cr_image_path': c.crImagePath,
        'vat_certificate_path': c.vatCertificatePath,
        'customer_photo_path': c.customerPhotoPath,
        'created_at': c.createdAt.toIso8601String(),
        'updated_at': c.updatedAt.toIso8601String(),
      };

  CustomerModel _customerFromRow(Map<String, Object?> r) {
    return CustomerModel(
      id: '${r['id']}',
      clientId: '${r['client_id']}',
      erpName: r['erp_name'] == null ? null : '${r['erp_name']}',
      syncStatus: _syncStatusFrom('${r['sync_status']}'),
      lastError: r['last_error'] == null ? null : '${r['last_error']}',
      customerName: '${r['customer_name']}',
      customerNameAr:
          r['customer_name_ar'] == null ? null : '${r['customer_name_ar']}',
      customerType: '${r['customer_type']}',
      customerGroup: '${r['customer_group']}',
      territory: '${r['territory']}',
      taxId: r['tax_id'] == null ? null : '${r['tax_id']}',
      crNumber: r['cr_number'] == null ? null : '${r['cr_number']}',
      customerCode:
          r['customer_code'] == null ? null : '${r['customer_code']}',
      website: r['website'] == null ? null : '${r['website']}',
      industry: r['industry'] == null ? null : '${r['industry']}',
      mobileNo: '${r['mobile_no']}',
      phone: r['phone'] == null ? null : '${r['phone']}',
      email: r['email'] == null ? null : '${r['email']}',
      addressLine1: '${r['address_line1']}',
      addressLine2:
          r['address_line2'] == null ? null : '${r['address_line2']}',
      city: '${r['city']}',
      state: r['state'] == null ? null : '${r['state']}',
      country: '${r['country']}',
      postalCode: r['postal_code'] == null ? null : '${r['postal_code']}',
      googleMapUrl:
          r['google_map_url'] == null ? null : '${r['google_map_url']}',
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
      priceList: r['price_list'] == null ? null : '${r['price_list']}',
      salesPerson: r['sales_person'] == null ? null : '${r['sales_person']}',
      creditLimit: (r['credit_limit'] as num?)?.toDouble(),
      paymentTerms:
          r['payment_terms'] == null ? null : '${r['payment_terms']}',
      currency: r['currency'] == null ? null : '${r['currency']}',
      enabled: (r['enabled'] as num?)?.toInt() != 0,
      remarks: r['remarks'] == null ? null : '${r['remarks']}',
      crImagePath:
          r['cr_image_path'] == null ? null : '${r['cr_image_path']}',
      vatCertificatePath: r['vat_certificate_path'] == null
          ? null
          : '${r['vat_certificate_path']}',
      customerPhotoPath: r['customer_photo_path'] == null
          ? null
          : '${r['customer_photo_path']}',
      createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${r['updated_at']}') ?? DateTime.now(),
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
    await db.insert('sync_queue', {
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
    }, conflictAlgorithm: conflict);
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
      // Customers first so sales/collections can resolve ERP names.
      final rows = await txn.rawQuery('''
SELECT * FROM sync_queue
WHERE status = 'queued'
ORDER BY CASE entity_type WHEN 'customer' THEN 0 ELSE 1 END, created_at ASC
LIMIT 1
''');
      if (rows.isEmpty) return null;
      final item = _queueFromRow(rows.first);
      await txn.update(
        'sync_queue',
        {'status': 'in_flight', 'attempts': item.attempts + 1},
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
      {'status': 'awaiting_erp', 'last_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markQueueFailed(String id, String error) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 'failed', 'last_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> requeueFailed(String id) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 'queued', 'last_error': null},
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
      collectedAt: DateTime.tryParse('${r['collected_at']}') ?? DateTime.now(),
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

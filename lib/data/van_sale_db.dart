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
import '../product/models/product_model.dart';

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

  /// Close and drop the cached connection (used by backup restore).
  Future<void> closeDatabase() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<String> databasePath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, 'van_sale.db');
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'van_sale.db');
    return openDatabase(
      path,
      version: 6,
      onConfigure: (db) async {
        // Android sqflite rejects execute() for busy_timeout; rawQuery works.
        try {
          await db.rawQuery('PRAGMA busy_timeout = 5000');
        } catch (_) {
          try {
            await db.execute('PRAGMA busy_timeout = 5000');
          } catch (_) {}
        }
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        await _createCustomersTable(db);
        await _createCustomerSearchTables(db);
        await _createCustomerIndexes(db);
        await _createCustomerSearchIndexes(db);
        await _createProductsTable(db);
        await _createProductSearchTables(db);
        await _createProductIndexes(db);
        await _createProductSearchIndexes(db);
        await _createSyncLogsTable(db);
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
        if (oldVersion < 3) {
          await _createProductsTable(db);
          await _createProductIndexes(db);
        }
        if (oldVersion < 4) {
          await _createSyncLogsTable(db);
          await db.execute(
            "UPDATE sync_queue SET status = 'pending' WHERE status IN ('queued','awaiting_erp')",
          );
          await db.execute(
            "UPDATE sync_queue SET status = 'uploading' WHERE status IN ('in_flight')",
          );
          try {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN erp_modified TEXT',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN erp_modified TEXT',
            );
          } catch (_) {}
        }
        if (oldVersion < 5) {
          try {
            await db.execute('ALTER TABLE customers ADD COLUMN barcode TEXT');
          } catch (_) {}
          await _createCustomerSearchTables(db);
          await _createCustomerIndexes(db);
          await _createCustomerSearchIndexes(db);
        }
        if (oldVersion < 6) {
          await _createProductSearchTables(db);
          await _createProductIndexes(db);
          await _createProductSearchIndexes(db);
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
  erp_modified TEXT,
  barcode TEXT,
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_mobile ON customers(mobile_no)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_tax ON customers(tax_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_cr ON customers(cr_number)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name_ar ON customers(customer_name_ar)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_code ON customers(customer_code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_barcode ON customers(barcode)',
    );
  }

  Future<void> _createCustomerSearchTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS customer_favorites (
  customer_id TEXT PRIMARY KEY NOT NULL,
  created_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS customer_recent (
  customer_id TEXT PRIMARY KEY NOT NULL,
  used_at TEXT NOT NULL
)''');
  }

  Future<void> _createCustomerSearchIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_recent_used ON customer_recent(used_at DESC)',
    );
  }

  Future<void> _createProductsTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY NOT NULL,
  client_id TEXT NOT NULL UNIQUE,
  erp_name TEXT,
  sync_status TEXT NOT NULL,
  last_error TEXT,
  item_code TEXT NOT NULL UNIQUE,
  item_name TEXT NOT NULL,
  item_name_ar TEXT,
  item_group TEXT NOT NULL,
  stock_uom TEXT NOT NULL,
  sales_uom TEXT,
  description TEXT,
  brand TEXT,
  barcode TEXT,
  sku TEXT,
  hs_code TEXT,
  selling_rate REAL NOT NULL DEFAULT 0,
  purchase_rate REAL NOT NULL DEFAULT 0,
  price_list TEXT,
  tax_template TEXT,
  maintain_stock INTEGER NOT NULL DEFAULT 1,
  disabled INTEGER NOT NULL DEFAULT 0,
  has_batch INTEGER NOT NULL DEFAULT 0,
  has_serial INTEGER NOT NULL DEFAULT 0,
  opening_quantity REAL NOT NULL DEFAULT 0,
  opening_warehouse TEXT,
  reorder_level REAL,
  weight REAL,
  weight_uom TEXT,
  income_account TEXT,
  expense_account TEXT,
  cost_center TEXT,
  image_path TEXT,
  gallery_paths_json TEXT,
  erp_modified TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''');
  }

  Future<void> _createProductIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_sync ON products(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_name ON products(item_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_name_ar ON products(item_name_ar)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_code ON products(item_code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_group ON products(item_group)',
    );
  }

  Future<void> _createProductSearchTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS product_favorites (
  product_id TEXT PRIMARY KEY NOT NULL,
  created_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS product_recent (
  product_id TEXT PRIMARY KEY NOT NULL,
  used_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS product_sales_stats (
  item_code TEXT PRIMARY KEY NOT NULL,
  sold_qty REAL NOT NULL DEFAULT 0,
  sold_count INTEGER NOT NULL DEFAULT 0,
  last_sold_at TEXT NOT NULL
)''');
  }

  Future<void> _createProductSearchIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_recent_used ON product_recent(used_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_sales_qty ON product_sales_stats(sold_qty DESC)',
    );
  }

  Future<void> _createSyncLogsTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS sync_logs (
  id TEXT PRIMARY KEY NOT NULL,
  level TEXT NOT NULL,
  message TEXT NOT NULL,
  entity_type TEXT,
  entity_id TEXT,
  queue_id TEXT,
  created_at TEXT NOT NULL
)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_logs_created ON sync_logs(created_at DESC)',
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

  Future<void> upsertStockLine(
    StockLine line, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
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
    double? amount,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.update(
      'van_orders',
      {
        'sync_status': status.name,
        'erp_name': ?erpName,
        'amount': ?amount,
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

  Future<void> upsertCustomer(
    CustomerModel c, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.insert(
      'customers',
      _customerToRow(c),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CustomerModel?> getCustomer(String id) async {
    final db = await database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _customerFromRow(rows.first);
  }

  Future<List<CustomerModel>> listCustomers({
    String? query,
    bool enabledOnly = true,
  }) async {
    final page = await searchCustomers(
      query: query,
      enabledOnly: enabledOnly,
      limit: 5000,
      offset: 0,
    );
    return page.items;
  }

  /// Offline multi-field customer search with pagination.
  Future<CustomerSearchResult> searchCustomers({
    String? query,
    int limit = 30,
    int offset = 0,
    bool enabledOnly = true,
    bool favoritesOnly = false,
    bool recentOnly = false,
  }) async {
    final db = await database;
    final where = <String>['1=1'];
    final args = <Object?>[];

    if (enabledOnly) {
      where.add('c.enabled = 1');
    }

    final q = query?.trim() ?? '';
    if (q.isNotEmpty) {
      final like = '%$q%';
      where.add('''(
  c.customer_name LIKE ? COLLATE NOCASE
  OR c.customer_name_ar LIKE ? COLLATE NOCASE
  OR c.mobile_no LIKE ?
  OR c.phone LIKE ?
  OR c.tax_id LIKE ? COLLATE NOCASE
  OR c.cr_number LIKE ? COLLATE NOCASE
  OR c.customer_code LIKE ? COLLATE NOCASE
  OR c.email LIKE ? COLLATE NOCASE
  OR c.erp_name LIKE ? COLLATE NOCASE
  OR c.barcode LIKE ?
)''');
      args.addAll([like, like, like, like, like, like, like, like, like, like]);
    }

    final whereSql = where.join(' AND ');
    late final String countSql;
    late final String listSql;
    late final String orderBy;

    if (favoritesOnly) {
      orderBy = 'f.created_at DESC';
      countSql =
          'SELECT COUNT(*) AS c FROM customers c INNER JOIN customer_favorites f ON f.customer_id = c.id WHERE $whereSql';
      listSql =
          '''
SELECT c.*, 1 AS is_favorite
FROM customers c
INNER JOIN customer_favorites f ON f.customer_id = c.id
WHERE $whereSql
ORDER BY $orderBy
LIMIT ? OFFSET ?
''';
    } else if (recentOnly) {
      orderBy = 'r.used_at DESC';
      countSql =
          'SELECT COUNT(*) AS c FROM customers c INNER JOIN customer_recent r ON r.customer_id = c.id WHERE $whereSql';
      listSql =
          '''
SELECT c.*,
  CASE WHEN fav.customer_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite
FROM customers c
INNER JOIN customer_recent r ON r.customer_id = c.id
LEFT JOIN customer_favorites fav ON fav.customer_id = c.id
WHERE $whereSql
ORDER BY $orderBy
LIMIT ? OFFSET ?
''';
    } else {
      orderBy = 'c.customer_name COLLATE NOCASE ASC';
      countSql = 'SELECT COUNT(*) AS c FROM customers c WHERE $whereSql';
      listSql =
          '''
SELECT c.*,
  CASE WHEN fav.customer_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite
FROM customers c
LEFT JOIN customer_favorites fav ON fav.customer_id = c.id
WHERE $whereSql
ORDER BY $orderBy
LIMIT ? OFFSET ?
''';
    }

    final countRows = await db.rawQuery(countSql, args);
    final total = (countRows.first['c'] as num?)?.toInt() ?? 0;

    final rows = await db.rawQuery(listSql, [...args, limit, offset]);
    final items = rows
        .map((r) {
          final model = _customerFromRow(r);
          final fav = (r['is_favorite'] as num?)?.toInt() == 1;
          return model.copyWith(isFavorite: fav);
        })
        .toList(growable: false);

    return CustomerSearchResult(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
      hasMore: offset + items.length < total,
    );
  }

  Future<CustomerModel?> findCustomerByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final db = await database;
    final rows = await db.rawQuery(
      '''
SELECT c.*,
  CASE WHEN f.customer_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite
FROM customers c
LEFT JOIN customer_favorites f ON f.customer_id = c.id
WHERE c.barcode = ? AND c.enabled = 1
LIMIT 1
''',
      [code],
    );
    if (rows.isEmpty) return null;
    final model = _customerFromRow(rows.first);
    final fav = (rows.first['is_favorite'] as num?)?.toInt() == 1;
    return model.copyWith(isFavorite: fav);
  }

  Future<void> setCustomerFavorite(String customerId, bool favorite) async {
    final db = await database;
    if (favorite) {
      await db.insert('customer_favorites', {
        'customer_id': customerId,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.delete(
        'customer_favorites',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
    }
  }

  Future<bool> isCustomerFavorite(String customerId) async {
    final db = await database;
    final rows = await db.query(
      'customer_favorites',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> touchCustomerRecent(String customerId) async {
    final db = await database;
    await db.insert('customer_recent', {
      'customer_id': customerId,
      'used_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // Keep last 50
    await _trimRecentTable('customer_recent', 'customer_id', keep: 50);
  }

  Future<void> _trimRecentTable(
    String table,
    String idColumn, {
    required int keep,
  }) async {
    final db = await database;
    await db.execute('''
DELETE FROM $table WHERE $idColumn NOT IN (
  SELECT $idColumn FROM (
    SELECT $idColumn FROM $table ORDER BY used_at DESC LIMIT $keep
  )
)''');
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
    String? erpModified,
    String? lastError,
  }) async {
    final db = await database;
    await db.update(
      'customers',
      {
        'sync_status': status.name,
        'erp_name': ?erpName,
        'erp_modified': ?erpModified,
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
    'erp_modified': c.erpModified,
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
    'barcode': c.barcode,
    'created_at': c.createdAt.toIso8601String(),
    'updated_at': c.updatedAt.toIso8601String(),
  };

  CustomerModel _customerFromRow(Map<String, Object?> r) {
    return CustomerModel(
      id: '${r['id']}',
      clientId: '${r['client_id']}',
      erpName: r['erp_name'] == null ? null : '${r['erp_name']}',
      erpModified: r['erp_modified'] == null ? null : '${r['erp_modified']}',
      syncStatus: _syncStatusFrom('${r['sync_status']}'),
      lastError: r['last_error'] == null ? null : '${r['last_error']}',
      customerName: '${r['customer_name']}',
      customerNameAr: r['customer_name_ar'] == null
          ? null
          : '${r['customer_name_ar']}',
      customerType: '${r['customer_type']}',
      customerGroup: '${r['customer_group']}',
      territory: '${r['territory']}',
      taxId: r['tax_id'] == null ? null : '${r['tax_id']}',
      crNumber: r['cr_number'] == null ? null : '${r['cr_number']}',
      customerCode: r['customer_code'] == null ? null : '${r['customer_code']}',
      website: r['website'] == null ? null : '${r['website']}',
      industry: r['industry'] == null ? null : '${r['industry']}',
      mobileNo: '${r['mobile_no'] ?? ''}',
      phone: r['phone'] == null ? null : '${r['phone']}',
      email: r['email'] == null ? null : '${r['email']}',
      addressLine1: '${r['address_line1'] ?? ''}',
      addressLine2: r['address_line2'] == null ? null : '${r['address_line2']}',
      city: '${r['city'] ?? ''}',
      state: r['state'] == null ? null : '${r['state']}',
      country: '${r['country'] ?? 'Saudi Arabia'}',
      postalCode: r['postal_code'] == null ? null : '${r['postal_code']}',
      googleMapUrl: r['google_map_url'] == null
          ? null
          : '${r['google_map_url']}',
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
      priceList: r['price_list'] == null ? null : '${r['price_list']}',
      salesPerson: r['sales_person'] == null ? null : '${r['sales_person']}',
      creditLimit: (r['credit_limit'] as num?)?.toDouble(),
      paymentTerms: r['payment_terms'] == null ? null : '${r['payment_terms']}',
      currency: r['currency'] == null ? null : '${r['currency']}',
      enabled: (r['enabled'] as num?)?.toInt() != 0,
      remarks: r['remarks'] == null ? null : '${r['remarks']}',
      barcode: r['barcode'] == null || '${r['barcode']}'.isEmpty
          ? null
          : '${r['barcode']}',
      crImagePath: r['cr_image_path'] == null ? null : '${r['cr_image_path']}',
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

  // --- products ---

  Future<void> upsertProduct(
    ProductModel p, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.insert(
      'products',
      _productToRow(p),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ProductModel?> getProduct(String id) async {
    final db = await database;
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.first);
  }

  Future<ProductModel?> getProductByCode(String itemCode) async {
    final db = await database;
    final rows = await db.query(
      'products',
      where: 'item_code = ?',
      whereArgs: [itemCode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.first);
  }

  Future<List<ProductModel>> listProducts({String? query}) async {
    final page = await searchProducts(query: query, limit: 5000, offset: 0);
    return page.items;
  }

  /// Offline multi-field product search with stock join + pagination.
  Future<ProductSearchResult> searchProducts({
    String? query,
    int limit = 30,
    int offset = 0,
    bool favoritesOnly = false,
    bool recentOnly = false,
    bool frequentOnly = false,
  }) async {
    final db = await database;
    final where = <String>['p.disabled = 0'];
    final args = <Object?>[];

    final q = query?.trim() ?? '';
    if (q.isNotEmpty) {
      final like = '%$q%';
      where.add('''(
  p.item_code LIKE ? COLLATE NOCASE
  OR p.item_name LIKE ? COLLATE NOCASE
  OR p.item_name_ar LIKE ? COLLATE NOCASE
  OR p.barcode LIKE ?
  OR p.sku LIKE ? COLLATE NOCASE
  OR p.brand LIKE ? COLLATE NOCASE
  OR p.item_group LIKE ? COLLATE NOCASE
  OR p.erp_name LIKE ? COLLATE NOCASE
  OR CAST(p.selling_rate AS TEXT) LIKE ?
)''');
      args.addAll([like, like, like, like, like, like, like, like, like]);
    }

    final whereSql = where.join(' AND ');
    late final String countSql;
    late final String listSql;

    if (favoritesOnly) {
      countSql =
          'SELECT COUNT(*) AS c FROM products p INNER JOIN product_favorites f ON f.product_id = p.id WHERE $whereSql';
      listSql =
          '''
SELECT p.*,
  1 AS is_favorite,
  COALESCE(s.qty, 0) AS stock_qty,
  COALESCE(s.unit_price, p.selling_rate) AS stock_unit_price
FROM products p
INNER JOIN product_favorites f ON f.product_id = p.id
LEFT JOIN van_stock s ON s.item_code = p.item_code
WHERE $whereSql
ORDER BY f.created_at DESC
LIMIT ? OFFSET ?
''';
    } else if (recentOnly) {
      countSql =
          'SELECT COUNT(*) AS c FROM products p INNER JOIN product_recent r ON r.product_id = p.id WHERE $whereSql';
      listSql =
          '''
SELECT p.*,
  CASE WHEN fav.product_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite,
  COALESCE(s.qty, 0) AS stock_qty,
  COALESCE(s.unit_price, p.selling_rate) AS stock_unit_price
FROM products p
INNER JOIN product_recent r ON r.product_id = p.id
LEFT JOIN product_favorites fav ON fav.product_id = p.id
LEFT JOIN van_stock s ON s.item_code = p.item_code
WHERE $whereSql
ORDER BY r.used_at DESC
LIMIT ? OFFSET ?
''';
    } else if (frequentOnly) {
      countSql =
          '''
SELECT COUNT(*) AS c FROM products p
INNER JOIN product_sales_stats st ON st.item_code = p.item_code
WHERE $whereSql AND st.sold_count > 0
''';
      listSql =
          '''
SELECT p.*,
  CASE WHEN fav.product_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite,
  COALESCE(s.qty, 0) AS stock_qty,
  COALESCE(s.unit_price, p.selling_rate) AS stock_unit_price
FROM products p
INNER JOIN product_sales_stats st ON st.item_code = p.item_code
LEFT JOIN product_favorites fav ON fav.product_id = p.id
LEFT JOIN van_stock s ON s.item_code = p.item_code
WHERE $whereSql AND st.sold_count > 0
ORDER BY st.sold_qty DESC, st.sold_count DESC
LIMIT ? OFFSET ?
''';
    } else {
      countSql = 'SELECT COUNT(*) AS c FROM products p WHERE $whereSql';
      listSql =
          '''
SELECT p.*,
  CASE WHEN fav.product_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite,
  COALESCE(s.qty, 0) AS stock_qty,
  COALESCE(s.unit_price, p.selling_rate) AS stock_unit_price
FROM products p
LEFT JOIN product_favorites fav ON fav.product_id = p.id
LEFT JOIN van_stock s ON s.item_code = p.item_code
WHERE $whereSql
ORDER BY p.item_name COLLATE NOCASE ASC
LIMIT ? OFFSET ?
''';
    }

    final countRows = await db.rawQuery(countSql, args);
    final total = (countRows.first['c'] as num?)?.toInt() ?? 0;
    final rows = await db.rawQuery(listSql, [...args, limit, offset]);
    final items = rows.map(_productFromSearchRow).toList(growable: false);

    return ProductSearchResult(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
      hasMore: offset + items.length < total,
    );
  }

  ProductModel _productFromSearchRow(Map<String, Object?> r) {
    final model = _productFromRow(r);
    return model.copyWith(
      isFavorite: (r['is_favorite'] as num?)?.toInt() == 1,
      stockQty: (r['stock_qty'] as num?)?.toDouble() ?? 0,
      stockUnitPrice: (r['stock_unit_price'] as num?)?.toDouble(),
    );
  }

  Future<ProductModel?> findProductByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final db = await database;
    final rows = await db.rawQuery(
      '''
SELECT p.*,
  CASE WHEN fav.product_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite,
  COALESCE(s.qty, 0) AS stock_qty,
  COALESCE(s.unit_price, p.selling_rate) AS stock_unit_price
FROM products p
LEFT JOIN product_favorites fav ON fav.product_id = p.id
LEFT JOIN van_stock s ON s.item_code = p.item_code
WHERE p.disabled = 0 AND p.barcode = ?
LIMIT 1
''',
      [code],
    );
    if (rows.isEmpty) return null;
    return _productFromSearchRow(rows.first);
  }

  Future<void> setProductFavorite(String productId, bool favorite) async {
    final db = await database;
    if (favorite) {
      await db.insert('product_favorites', {
        'product_id': productId,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.delete(
        'product_favorites',
        where: 'product_id = ?',
        whereArgs: [productId],
      );
    }
  }

  Future<void> touchProductRecent(String productId) async {
    final db = await database;
    await db.insert('product_recent', {
      'product_id': productId,
      'used_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _trimRecentTable('product_recent', 'product_id', keep: 50);
  }

  Future<void> recordProductSales(List<OrderLine> lines) async {
    if (lines.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final line in lines) {
        final existing = await txn.query(
          'product_sales_stats',
          where: 'item_code = ?',
          whereArgs: [line.itemCode],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('product_sales_stats', {
            'item_code': line.itemCode,
            'sold_qty': line.qty,
            'sold_count': 1,
            'last_sold_at': now,
          });
        } else {
          final row = existing.first;
          await txn.update(
            'product_sales_stats',
            {
              'sold_qty':
                  ((row['sold_qty'] as num?)?.toDouble() ?? 0) + line.qty,
              'sold_count': ((row['sold_count'] as num?)?.toInt() ?? 0) + 1,
              'last_sold_at': now,
            },
            where: 'item_code = ?',
            whereArgs: [line.itemCode],
          );
        }
      }
    });
  }

  Future<ProductModel?> findProductDuplicate({
    String? itemCode,
    String? barcode,
    String? excludeId,
  }) async {
    final db = await database;
    if (itemCode != null && itemCode.trim().isNotEmpty) {
      final rows = await db.query(
        'products',
        where: excludeId == null
            ? 'item_code = ?'
            : 'item_code = ? AND id != ?',
        whereArgs: excludeId == null
            ? [itemCode.trim()]
            : [itemCode.trim(), excludeId],
        limit: 1,
      );
      if (rows.isNotEmpty) return _productFromRow(rows.first);
    }
    if (barcode != null && barcode.trim().isNotEmpty) {
      final rows = await db.query(
        'products',
        where: excludeId == null ? 'barcode = ?' : 'barcode = ? AND id != ?',
        whereArgs: excludeId == null
            ? [barcode.trim()]
            : [barcode.trim(), excludeId],
        limit: 1,
      );
      if (rows.isNotEmpty) return _productFromRow(rows.first);
    }
    return null;
  }

  Future<void> setProductSync({
    required String id,
    required SyncStatus status,
    String? erpName,
    String? erpModified,
    String? lastError,
  }) async {
    final db = await database;
    await db.update(
      'products',
      {
        'sync_status': status.name,
        'erp_name': ?erpName,
        'erp_modified': ?erpModified,
        'last_error': lastError,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Map<String, Object?> _productToRow(ProductModel p) => {
    'id': p.id,
    'client_id': p.clientId,
    'erp_name': p.erpName,
    'erp_modified': p.erpModified,
    'sync_status': p.syncStatus.name,
    'last_error': p.lastError,
    'item_code': p.itemCode,
    'item_name': p.itemName,
    'item_name_ar': p.itemNameAr,
    'item_group': p.itemGroup,
    'stock_uom': p.stockUom,
    'sales_uom': p.salesUom,
    'description': p.description,
    'brand': p.brand,
    'barcode': p.barcode,
    'sku': p.sku,
    'hs_code': p.hsCode,
    'selling_rate': p.sellingRate,
    'purchase_rate': p.purchaseRate,
    'price_list': p.priceList,
    'tax_template': p.taxTemplate,
    'maintain_stock': p.maintainStock ? 1 : 0,
    'disabled': p.disabled ? 1 : 0,
    'has_batch': p.hasBatch ? 1 : 0,
    'has_serial': p.hasSerial ? 1 : 0,
    'opening_quantity': p.openingQuantity,
    'opening_warehouse': p.openingWarehouse,
    'reorder_level': p.reorderLevel,
    'weight': p.weight,
    'weight_uom': p.weightUom,
    'income_account': p.incomeAccount,
    'expense_account': p.expenseAccount,
    'cost_center': p.costCenter,
    'image_path': p.imagePath,
    'gallery_paths_json': jsonEncode(p.galleryPaths),
    'created_at': p.createdAt.toIso8601String(),
    'updated_at': p.updatedAt.toIso8601String(),
  };

  ProductModel _productFromRow(Map<String, Object?> r) {
    List<String> gallery = const [];
    final raw = r['gallery_paths_json'];
    if (raw != null) {
      final decoded = jsonDecode('$raw');
      if (decoded is List) {
        gallery = decoded.map((e) => '$e').toList(growable: false);
      }
    }
    return ProductModel(
      id: '${r['id']}',
      clientId: '${r['client_id']}',
      erpName: r['erp_name'] == null ? null : '${r['erp_name']}',
      erpModified: r['erp_modified'] == null ? null : '${r['erp_modified']}',
      syncStatus: _syncStatusFrom('${r['sync_status']}'),
      lastError: r['last_error'] == null ? null : '${r['last_error']}',
      itemCode: '${r['item_code']}',
      itemName: '${r['item_name']}',
      itemNameAr: r['item_name_ar'] == null ? null : '${r['item_name_ar']}',
      itemGroup: '${r['item_group']}',
      stockUom: '${r['stock_uom']}',
      salesUom: r['sales_uom'] == null ? null : '${r['sales_uom']}',
      description: r['description'] == null ? null : '${r['description']}',
      brand: r['brand'] == null ? null : '${r['brand']}',
      barcode: r['barcode'] == null ? null : '${r['barcode']}',
      sku: r['sku'] == null ? null : '${r['sku']}',
      hsCode: r['hs_code'] == null ? null : '${r['hs_code']}',
      sellingRate: (r['selling_rate'] as num?)?.toDouble() ?? 0,
      purchaseRate: (r['purchase_rate'] as num?)?.toDouble() ?? 0,
      priceList: r['price_list'] == null ? null : '${r['price_list']}',
      taxTemplate: r['tax_template'] == null ? null : '${r['tax_template']}',
      maintainStock: (r['maintain_stock'] as num?)?.toInt() != 0,
      disabled: (r['disabled'] as num?)?.toInt() == 1,
      hasBatch: (r['has_batch'] as num?)?.toInt() == 1,
      hasSerial: (r['has_serial'] as num?)?.toInt() == 1,
      openingQuantity: (r['opening_quantity'] as num?)?.toDouble() ?? 0,
      openingWarehouse: r['opening_warehouse'] == null
          ? null
          : '${r['opening_warehouse']}',
      reorderLevel: (r['reorder_level'] as num?)?.toDouble(),
      weight: (r['weight'] as num?)?.toDouble(),
      weightUom: r['weight_uom'] == null ? null : '${r['weight_uom']}',
      incomeAccount: r['income_account'] == null
          ? null
          : '${r['income_account']}',
      expenseAccount: r['expense_account'] == null
          ? null
          : '${r['expense_account']}',
      costCenter: r['cost_center'] == null ? null : '${r['cost_center']}',
      imagePath: r['image_path'] == null ? null : '${r['image_path']}',
      galleryPaths: gallery,
      createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${r['updated_at']}') ?? DateTime.now(),
    );
  }

  Future<void> deleteCustomerRow(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteProductRow(String id, {DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearQueueForEntity(
    String entityType,
    String entityId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
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
    var id = 'sq_${entityType}_${entityId}_$op';
    // Never replace an in-flight row — a successful flush would delete the
    // newer args that replaced it mid-upload.
    if (conflict == ConflictAlgorithm.replace) {
      final existing = await db.query(
        'sync_queue',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          '${existing.first['status']}' == 'uploading') {
        id =
            'sq_${entityType}_${entityId}_${op}_${DateTime.now().millisecondsSinceEpoch}';
        conflict = ConflictAlgorithm.abort;
      }
    }
    await db.insert('sync_queue', {
      'id': id,
      'client_id': clientId,
      'entity_type': entityType,
      'entity_id': entityId,
      'op': op,
      'method': method,
      'args_json': jsonEncode(args),
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: conflict);
  }

  Future<List<SyncQueueItem>> peekQueue({
    List<String> statuses = const ['pending', 'retry'],
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
WHERE status IN ('pending', 'retry', 'queued')
ORDER BY CASE entity_type
  WHEN 'customer' THEN 0
  WHEN 'product' THEN 1
  ELSE 2 END, created_at ASC
LIMIT 1
''');
      if (rows.isEmpty) return null;
      final item = _queueFromRow(rows.first);
      await txn.update(
        'sync_queue',
        {'status': 'uploading', 'attempts': item.attempts + 1},
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
        status: 'uploading',
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

  /// Entity ids that still have open sync_queue rows (any non-terminal status).
  Future<Set<String>> entityIdsWithOpenQueue(String entityType) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
SELECT DISTINCT entity_id FROM sync_queue
WHERE entity_type = ?
  AND status IN ('pending', 'retry', 'queued', 'failed', 'uploading', 'conflict')
''',
      [entityType],
    );
    return {for (final r in rows) '${r['entity_id']}'};
  }

  Future<bool> hasOpenQueueForEntityTypes(List<String> entityTypes) async {
    if (entityTypes.isEmpty) return false;
    final db = await database;
    final placeholders = List.filled(entityTypes.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
SELECT 1 FROM sync_queue
WHERE entity_type IN ($placeholders)
  AND status IN ('pending', 'retry', 'queued', 'failed', 'uploading', 'conflict')
LIMIT 1
''',
      entityTypes,
    );
    return rows.isNotEmpty;
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

  Future<void> markQueueConflict(String id, String error) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 'conflict', 'last_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markQueueRetry(String id) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 'retry', 'last_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> requeueFailed(String id) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 'retry', 'last_error': null},
      where: 'id = ? AND status IN (?, ?, ?)',
      whereArgs: [id, 'failed', 'conflict', 'retry'],
    );
  }

  Future<int> requeueAllFailed() async {
    final db = await database;
    return db.update('sync_queue', {
      'status': 'retry',
      'last_error': null,
    }, where: "status IN ('failed','conflict')");
  }

  Future<void> requeueInFlightAsQueued() async {
    final db = await database;
    await db.update('sync_queue', {
      'status': 'pending',
    }, where: "status IN ('uploading','in_flight')");
  }

  Future<void> addSyncLog({
    required String level,
    required String message,
    String? entityType,
    String? entityId,
    String? queueId,
  }) async {
    final db = await database;
    await db.insert('sync_logs', {
      'id': newLocalId('log'),
      'level': level,
      'message': message,
      'entity_type': entityType,
      'entity_id': entityId,
      'queue_id': queueId,
      'created_at': DateTime.now().toIso8601String(),
    });
    // Keep last 500
    await db.rawDelete('''
DELETE FROM sync_logs WHERE id NOT IN (
  SELECT id FROM sync_logs ORDER BY created_at DESC LIMIT 500
)
''');
  }

  Future<List<Map<String, Object?>>> listSyncLogs({int limit = 100}) async {
    final db = await database;
    return db.query('sync_logs', orderBy: 'created_at DESC', limit: limit);
  }

  Future<List<SyncQueueItem>> listQueueByStatuses(List<String> statuses) async {
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

  Future<Map<String, int>> syncCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS c FROM sync_queue GROUP BY status',
    );
    final out = <String, int>{
      'pending': 0,
      'uploading': 0,
      'uploaded': 0,
      'conflict': 0,
      'failed': 0,
      'retry': 0,
      // legacy keys for Today chips
      'queued': 0,
      'in_flight': 0,
      'awaiting_erp': 0,
    };
    for (final r in rows) {
      final status = '${r['status']}';
      final c = (r['c'] as num).toInt();
      out[status] = c;
      if (status == 'pending' || status == 'queued') {
        out['queued'] = (out['queued'] ?? 0) + c;
        out['pending'] = (out['pending'] ?? 0) + (status == 'pending' ? c : 0);
      }
      if (status == 'uploading' || status == 'in_flight') {
        out['in_flight'] = (out['in_flight'] ?? 0) + c;
        out['uploading'] =
            (out['uploading'] ?? 0) + (status == 'uploading' ? c : 0);
      }
    }
    out['pending'] = (out['pending'] ?? 0) + (out['retry'] ?? 0);
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
        .where((o) => o.syncStatus != SyncStatus.uploaded)
        .length;
    final collected = collections
        .where(_isLocalDay)
        .fold<double>(0, (s, c) => s + c.amount);
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
      syncConflict: counts['conflict'] ?? 0,
      syncRetry: counts['retry'] ?? 0,
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
      'pending' ||
      'queued' ||
      'awaitingErp' ||
      'awaiting_erp' => SyncStatus.pending,
      'uploading' || 'inFlight' || 'in_flight' => SyncStatus.uploading,
      'uploaded' || 'synced' => SyncStatus.uploaded,
      'conflict' => SyncStatus.conflict,
      'failed' => SyncStatus.failed,
      'retry' => SyncStatus.retry,
      _ => SyncStatus.pending,
    };
  }

  bool _isLocalDay(Collection c) {
    final now = DateTime.now();
    final d = c.collectedAt;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

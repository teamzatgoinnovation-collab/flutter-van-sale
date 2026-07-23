import 'package:sqflite/sqflite.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import '../customer/repositories/customer_repository.dart';
import '../customer/validation/customer_validators.dart';
import '../product/repositories/product_repository.dart';
import '../product/validation/product_validators.dart';
import '../models/models.dart';
import '../services/prefs.dart';
import '../services/session.dart';
import '../services/van_sale_policy.dart';
import 'van_sale_db.dart';

/// Local-first VanSale repository backed by ERPNext via go_van APIs.
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

  Future<StockLine?> getStock(String itemCode) => db.getStock(itemCode);

  Future<DaySummary> summary() => db.summary();

  Future<Map<String, int>> syncCounts() => db.syncCounts();

  Future<void> refreshFromErpnext(VanSaleSession session) async {
    if (!session.connected) return;
    try {
      await session.store.callMethod(ZatGoApiMethods.goVanPing);
      final env = await session.store.callMethod(
        ZatGoApiMethods.goVanTripsList,
        args: {'page': 1, 'page_size': 100},
      );
      final rows = _asList(env.data);
      final existingStatuses = <String, VisitStatus>{};
      for (final s in await db.listStops()) {
        existingStatuses[s.id] = s.visitStatus;
      }
      await db.clearStops();
      for (var i = 0; i < rows.length; i++) {
        final map = Map<String, dynamic>.from(rows[i] as Map);
        final id = '${map['name'] ?? map['id'] ?? 'trip-$i'}';
        final statusRaw = '${map['status'] ?? ''}';
        final fromErp = _visitFromErp(statusRaw);
        await db.upsertStop(
          RouteStop(
            id: id,
            customerName:
                '${map['customer'] ?? map['title'] ?? 'Stop ${i + 1}'}',
            address: '${map['address'] ?? ''}',
            sequence: (map['sequence'] as num?)?.toInt() ?? i + 1,
            lat: double.tryParse('${map['lat'] ?? ''}') ?? 0,
            lng: double.tryParse('${map['lng'] ?? ''}') ?? 0,
            plannedAt:
                DateTime.tryParse('${map['planned_at'] ?? ''}') ??
                DateTime.now(),
            visitStatus: fromErp ?? existingStatuses[id] ?? VisitStatus.planned,
          ),
        );
      }
      await db.metaSet('last_pull_at', DateTime.now().toIso8601String());
      await db.metaSet('route_name', 'Van route');
      routeName = 'Van route';

      final profileWh = session.context?.profile?.warehouse.trim() ?? '';
      if (profileWh.isNotEmpty &&
          VanSalePrefs.instance.warehouse.trim().isEmpty) {
        await VanSalePrefs.instance.setWarehouse(profileWh);
      }
      final warehouse = VanSalePrefs.instance.warehouse.trim().isNotEmpty
          ? VanSalePrefs.instance.warehouse.trim()
          : profileWh;
      if (warehouse.isNotEmpty) {
        final stockEnv = await session.store.callMethod(
          ZatGoApiMethods.goVanStockList,
          args: {'warehouse': warehouse, 'page': 1, 'page_size': 200},
        );
        final stockRows = _asList(stockEnv.data);
        final lines = <StockLine>[
          for (final raw in stockRows)
            if (raw is Map)
              StockLine(
                itemCode: '${raw['item_code'] ?? ''}',
                itemName: '${raw['item_name'] ?? raw['item_code'] ?? ''}',
                qty: (raw['qty'] as num?)?.toDouble() ?? 0,
                uom: '${raw['uom'] ?? 'Nos'}',
                unitPrice:
                    (raw['unit_price'] as num?)?.toDouble() ??
                    (raw['rate'] as num?)?.toDouble() ??
                    0,
              ),
        ];
        await db.replaceStock(
          lines.where((l) => l.itemCode.isNotEmpty).toList(),
        );
      }
    } catch (_) {
      // Keep local SQLite state on pull failure.
    }
  }

  Future<VanOrder> createOrder({
    required String customerName,
    required List<OrderLine> lines,
    VanSaleSession? session,
    String? tripId,
  }) async {
    if (lines.isEmpty) {
      throw StateError('Order needs at least one stock line.');
    }
    await VanSalePolicy.instance.assertCanMutate(session);
    final amount = lines.fold<double>(0, (s, l) => s + l.amount);
    final clientId = newClientId();
    final id = newLocalId('ord');
    final warehouse = VanSalePrefs.instance.warehouse.trim();
    final company = VanSalePrefs.instance.company.trim();
    final allowNegative = VanSalePolicy.instance.allowNegativeStock;
    final trip = tripId?.trim() ?? '';
    final order = VanOrder(
      id: id,
      clientId: clientId,
      customerName: customerName,
      lines: lines,
      amount: amount,
      createdAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );

    final database = await db.database;
    await database.transaction((txn) async {
      for (final line in lines) {
        final stock = await db.getStock(line.itemCode, executor: txn);
        if (stock == null) {
          throw StateError('Unknown item ${line.itemCode}');
        }
        if (!allowNegative && stock.qty < line.qty) {
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
        method: ZatGoApiMethods.goVanOrdersCreate,
        args: {
          'client_id': clientId,
          'customer': customerName,
          'items': [
            for (final l in lines) {...l.toJson(), 'rate': l.unitPrice},
          ],
          if (warehouse.isNotEmpty) 'warehouse': warehouse,
          if (company.isNotEmpty) 'company': company,
          if (trip.isNotEmpty) 'trip_id': trip,
        },
        executor: txn,
      );
    });
    await db.recordProductSales(lines);
    return order;
  }

  Future<Collection> recordCollection({
    required String customerName,
    required double amount,
    required String method,
    String? salesInvoice,
    VanSaleSession? session,
  }) async {
    if (amount <= 0) throw StateError('Collection amount must be positive.');
    await VanSalePolicy.instance.assertCanMutate(session);
    final clientId = newClientId();
    final id = newLocalId('col');
    final row = Collection(
      id: id,
      clientId: clientId,
      customerName: customerName,
      amount: amount,
      method: method,
      collectedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );

    final database = await db.database;
    await database.transaction((txn) async {
      await db.insertCollection(row, executor: txn);
      await db.enqueue(
        clientId: clientId,
        entityType: 'collection',
        entityId: id,
        op: 'create',
        method: ZatGoApiMethods.goVanCollectionsCreate,
        args: {
          'client_id': clientId,
          'customer': customerName,
          'amount': amount,
          'method': method,
          if (salesInvoice != null && salesInvoice.isNotEmpty)
            'sales_invoice': salesInvoice,
        },
        executor: txn,
      );
    });
    return row;
  }

  Future<RouteStop?> updateVisit(
    String id,
    VisitStatus status, {
    double? lat,
    double? lng,
    String? notes,
    String? noSaleReason,
  }) async {
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
        method: ZatGoApiMethods.goVanVisitsUpdate,
        args: {
          'client_id': clientId,
          'stop_id': id,
          'visit_status': status.name,
          'lat': ?lat,
          'lng': ?lng,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (noSaleReason != null && noSaleReason.isNotEmpty)
            'no_sale_reason': noSaleReason,
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
    VanSaleSession? session,
  }) async {
    await VanSalePolicy.instance.assertCanMutate(session);
    final warehouse = VanSalePrefs.instance.warehouse.trim();
    if (warehouse.isEmpty) {
      throw StateError('Set van warehouse in Settings before adjusting stock.');
    }
    final company = VanSalePrefs.instance.company.trim();
    final allowNegative = VanSalePolicy.instance.allowNegativeStock;
    final database = await db.database;
    await database.transaction((txn) async {
      final stock = await db.getStock(itemCode, executor: txn);
      if (stock == null) throw StateError('Unknown item $itemCode');
      final next = stock.qty + delta;
      if (!allowNegative && next < 0) {
        throw StateError('Stock cannot go negative for ${stock.itemName}');
      }
      await db.setStockQty(itemCode, next, executor: txn);
      final clientId = newClientId();
      await db.enqueue(
        clientId: clientId,
        entityType: 'van_stock',
        entityId: clientId,
        op: 'update',
        method: ZatGoApiMethods.goVanStockAdjust,
        args: {
          'client_id': clientId,
          'item_code': itemCode,
          'delta': delta,
          'warehouse': warehouse,
          if (company.isNotEmpty) 'company': company,
        },
        executor: txn,
      );
    });
  }

  /// Material Transfer from depot / source WH into the van warehouse (or reverse).
  Future<void> transferStock({
    required String itemCode,
    required double qty,
    required String fromWarehouse,
    required String toWarehouse,
    VanSaleSession? session,
  }) async {
    await VanSalePolicy.instance.assertCanMutate(session);
    if (qty <= 0) throw StateError('Transfer qty must be positive');
    final from = fromWarehouse.trim();
    final to = toWarehouse.trim();
    if (from.isEmpty || to.isEmpty) {
      throw StateError('Set source and van warehouses in Settings.');
    }
    if (from == to) {
      throw StateError('Source and destination warehouses must differ.');
    }
    final vanWh = VanSalePrefs.instance.warehouse.trim();
    final company = VanSalePrefs.instance.company.trim();
    final allowNegative = VanSalePolicy.instance.allowNegativeStock;
    final database = await db.database;
    await database.transaction((txn) async {
      // Only adjust local van stock when transfer touches the configured van WH.
      if (vanWh.isNotEmpty && (to == vanWh || from == vanWh)) {
        final stock = await db.getStock(itemCode, executor: txn);
        if (stock == null && to == vanWh) {
          throw StateError(
            'Unknown item $itemCode on van — sync stock first or add product.',
          );
        }
        if (stock != null) {
          final delta = to == vanWh ? qty : -qty;
          final next = stock.qty + delta;
          if (!allowNegative && next < 0) {
            throw StateError('Stock cannot go negative for ${stock.itemName}');
          }
          await db.setStockQty(itemCode, next, executor: txn);
        }
      }
      final clientId = newClientId();
      await db.enqueue(
        clientId: clientId,
        entityType: 'van_stock',
        entityId: clientId,
        op: 'update',
        method: ZatGoApiMethods.goVanStockTransfer,
        args: {
          'client_id': clientId,
          'item_code': itemCode,
          'qty': qty,
          'from_warehouse': from,
          'to_warehouse': to,
          if (company.isNotEmpty) 'company': company,
        },
        executor: txn,
      );
    });
  }

  /// Offline-first customer create via [CustomerRepository].
  Future<String> createCustomer({
    required VanSaleSession session,
    required String customerName,
    String? phone,
    String? addressLine1,
    String? city,
    String? country,
  }) async {
    await customerRepository.loadDefaults(session);
    final d = customerRepository.defaults;
    final draft = CustomerDraft()
      ..applyDefaults(d)
      ..customerName = customerName
      ..mobileNo = phone?.trim() ?? ''
      ..addressLine1 = (addressLine1 ?? '').trim()
      ..city = (city ?? '').trim()
      ..country = (country ?? d.country).trim();
    final created = await customerRepository.createLocal(draft);
    if (session.connected) {
      // Flush is owned by SyncService callers; leave queued if offline.
    }
    return created.displayName;
  }

  /// Offline-first product create via [ProductRepository].
  Future<StockLine> createProduct({
    required VanSaleSession session,
    required String itemCode,
    required String itemName,
    required double unitPrice,
    double loadQty = 0,
    String uom = 'Nos',
    String? itemGroup,
  }) async {
    await productRepository.loadDefaults(session);
    final d = productRepository.defaults;
    final draft = ProductDraft()
      ..applyDefaults(d)
      ..itemCode = itemCode
      ..itemName = itemName
      ..stockUom = uom.isEmpty ? d.stockUom : uom
      ..salesUom = uom.isEmpty ? d.salesUom : uom
      ..sellingRate = unitPrice
      ..openingQuantity = loadQty
      ..openingWarehouse = VanSalePrefs.instance.warehouse.trim().isEmpty
          ? (d.openingWarehouse ?? '')
          : VanSalePrefs.instance.warehouse.trim();
    if (itemGroup != null && itemGroup.trim().isNotEmpty) {
      draft.itemGroup = itemGroup.trim();
    }
    final created = await productRepository.createLocal(draft);
    return StockLine(
      itemCode: created.itemCode,
      itemName: created.itemName,
      qty: created.openingQuantity,
      uom: created.stockUom,
      unitPrice: created.sellingRate,
    );
  }

  List<dynamic> _asList(Object? data) {
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    return const [];
  }

  VisitStatus? _visitFromErp(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v == 'planned') return VisitStatus.planned;
    if (v == 'checked in' || v == 'checkedin' || v == 'checked_in') {
      return VisitStatus.checkedIn;
    }
    if (v == 'completed' || v == 'done') return VisitStatus.completed;
    if (v == 'skipped') return VisitStatus.skipped;
    return null;
  }
}

final vanSaleRepo = VanSaleRepo(VanSaleDb.instance);

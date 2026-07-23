import 'package:sqflite/sqflite.dart';

import '../../core/cache/ttl_memory_cache.dart';
import '../../core/logging/app_logger.dart';
import '../../core/sync/string_utils.dart';
import '../../data/van_sale_db.dart';
import '../../models/models.dart';
import '../../services/prefs.dart';
import '../../services/session.dart';
import '../../services/van_sale_policy.dart';
import '../mappers/product_sync_mapper.dart';
import '../models/product_model.dart';
import '../validation/product_validators.dart';

/// ERPNext method paths for Item offline sync (ERPNext v16 compatible).
abstract final class ProductApiMethods {
  static const defaults = 'zatgo_core.api.v1.warehouse.items.defaults';
  static const sync = 'zatgo_core.api.v1.warehouse.items.sync';
  static const list = 'zatgo_core.api.v1.warehouse.items.list';
}

class ProductRepository {
  ProductRepository(this.db, {this.mapper = const ProductSyncMapper()});

  final VanSaleDb db;
  final ProductSyncMapper mapper;
  final _defaultsCache = TtlMemoryCache<ProductDefaults>();

  ProductDefaults _defaults = ProductDefaults.fallback();
  ProductDefaults get defaults => _defaults;

  Future<ProductDefaults> loadDefaults(VanSaleSession session) async {
    if (!session.connected) {
      final kept =
          _defaultsCache.peek ??
          (_defaults.itemGroups.isNotEmpty || _defaults.uoms.isNotEmpty
              ? _defaults
              : null);
      if (kept != null) {
        _defaults = kept;
      } else {
        _defaults = ProductDefaults.fallback();
      }
      final wh = VanSalePrefs.instance.warehouse.trim();
      final company = VanSalePrefs.instance.company.trim();
      if (wh.isNotEmpty || company.isNotEmpty) {
        _defaults = ProductDefaults(
          itemGroup: _defaults.itemGroup,
          stockUom: _defaults.stockUom,
          salesUom: _defaults.salesUom,
          company: company.isNotEmpty ? company : _defaults.company,
          defaultPriceList: _defaults.defaultPriceList,
          openingWarehouse: wh.isNotEmpty ? wh : _defaults.openingWarehouse,
          itemGroups: _defaults.itemGroups,
          uoms: _defaults.uoms,
          brands: _defaults.brands,
          priceLists: _defaults.priceLists,
          warehouses: _defaults.warehouses,
          itemTaxTemplates: _defaults.itemTaxTemplates,
          incomeAccounts: _defaults.incomeAccounts,
          expenseAccounts: _defaults.expenseAccounts,
          costCenters: _defaults.costCenters,
        );
      }
      return _defaults;
    }

    final cached = _defaultsCache.value;
    if (cached != null) {
      _defaults = cached;
    } else {
      try {
        final env = await session.store.callMethod(ProductApiMethods.defaults);
        if (env.data is Map) {
          _defaults = ProductDefaults.fromJson(
            Map<String, dynamic>.from(env.data as Map),
          );
          _defaultsCache.set(_defaults);
        }
      } catch (e) {
        AppLogger.warn(
          'product defaults fetch failed',
          tag: 'Product',
          error: e,
        );
      }
    }

    final wh = VanSalePrefs.instance.warehouse.trim();
    if ((_defaults.openingWarehouse ?? '').isEmpty && wh.isNotEmpty) {
      _defaults = ProductDefaults(
        itemGroup: _defaults.itemGroup,
        stockUom: _defaults.stockUom,
        salesUom: _defaults.salesUom,
        company: _defaults.company,
        defaultPriceList: _defaults.defaultPriceList,
        openingWarehouse: wh,
        itemGroups: _defaults.itemGroups,
        uoms: _defaults.uoms,
        brands: _defaults.brands,
        priceLists: _defaults.priceLists,
        warehouses: _defaults.warehouses,
        itemTaxTemplates: _defaults.itemTaxTemplates,
        incomeAccounts: _defaults.incomeAccounts,
        expenseAccounts: _defaults.expenseAccounts,
        costCenters: _defaults.costCenters,
      );
    }
    return _defaults;
  }

  /// Pull ERP catalog into local products (does not wipe pending local creates).
  Future<int> refreshFromErp(VanSaleSession session) async {
    if (!session.connected) return 0;
    var count = 0;
    try {
      for (var page = 1; page <= 10; page++) {
        final env = await session.store.callMethod(
          ProductApiMethods.list,
          args: {'page': page, 'page_size': 100},
        );
        final data = env.data;
        List rows = const [];
        if (data is List) {
          rows = data;
        } else if (data is Map && data['data'] is List) {
          rows = data['data'] as List;
        }
        if (rows.isEmpty) break;

        for (final raw in rows) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final code = '${map['item_code'] ?? map['id'] ?? map['name'] ?? ''}';
          if (code.isEmpty) continue;
          final existing = await db.getProductByCode(code);
          if (existing != null &&
              existing.syncStatus != SyncStatus.uploaded &&
              existing.erpName == null) {
            continue;
          }
          final now = DateTime.now();
          final rate =
              (map['standard_rate'] as num?)?.toDouble() ??
              (map['rate'] as num?)?.toDouble() ??
              existing?.sellingRate ??
              0;
          await db.upsertProduct(
            ProductModel(
              id: existing?.id ?? 'erp_$code',
              clientId: existing?.clientId ?? 'erp_$code',
              itemCode: code,
              itemName: '${map['item_name'] ?? map['name'] ?? code}',
              itemNameAr: map['item_name_ar'] == null
                  ? existing?.itemNameAr
                  : '${map['item_name_ar']}',
              itemGroup:
                  '${map['item_group'] ?? existing?.itemGroup ?? _defaults.itemGroup}',
              stockUom:
                  '${map['stock_uom'] ?? existing?.stockUom ?? _defaults.stockUom}',
              brand: map['brand'] == null ? existing?.brand : '${map['brand']}',
              barcode: map['barcode'] == null
                  ? existing?.barcode
                  : '${map['barcode']}',
              sku: map['sku'] == null ? existing?.sku : '${map['sku']}',
              sellingRate: rate,
              maintainStock: true,
              disabled: (map['disabled'] as num?)?.toInt() == 1,
              syncStatus: SyncStatus.uploaded,
              erpName: code,
              erpModified: map['modified'] == null
                  ? existing?.erpModified
                  : '${map['modified']}',
              imagePath:
                  existing?.imagePath ??
                  (map['image'] == null || '${map['image']}'.isEmpty
                      ? null
                      : '${map['image']}'),
              galleryPaths: existing?.galleryPaths ?? const [],
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
          final stock = await db.getStock(code);
          if (stock == null) {
            await db.upsertStockLine(
              StockLine(
                itemCode: code,
                itemName: '${map['item_name'] ?? code}',
                qty: 0,
                uom: '${map['stock_uom'] ?? 'Nos'}',
                unitPrice: rate,
              ),
            );
          }
          count++;
        }
        if (rows.length < 100) break;
      }
      return count;
    } catch (_) {
      return count;
    }
  }

  Future<List<ProductModel>> list({String? query}) =>
      db.listProducts(query: query);

  Future<ProductModel?> get(String id) => db.getProduct(id);

  Future<ProductSearchResult> search({
    String? query,
    int limit = 30,
    int offset = 0,
    ProductSearchScope scope = ProductSearchScope.all,
  }) {
    return db.searchProducts(
      query: query,
      limit: limit,
      offset: offset,
      favoritesOnly: scope == ProductSearchScope.favorites,
      recentOnly: scope == ProductSearchScope.recent,
      frequentOnly: scope == ProductSearchScope.frequent,
    );
  }

  Future<ProductModel?> findByBarcode(String barcode) =>
      db.findProductByBarcode(barcode);

  Future<ProductModel?> findByItemCode(String itemCode) =>
      db.getProductByCode(itemCode.trim());

  Future<void> toggleFavorite(String productId, {required bool favorite}) =>
      db.setProductFavorite(productId, favorite);

  Future<void> markRecent(String productId) => db.touchProductRecent(productId);

  Future<void> recordSales(List<OrderLine> lines) =>
      db.recordProductSales(lines);

  Future<ProductModel> createLocal(
    ProductDraft draft, {
    VanSaleSession? session,
  }) async {
    await VanSalePolicy.instance.assertCanMutate(session);
    draft.applyDefaults(_defaults);
    final errors = ProductValidators.validate(
      itemCode: draft.itemCode,
      itemName: draft.itemName,
      itemGroup: draft.itemGroup,
      stockUom: draft.stockUom,
      sellingRate: draft.sellingRate,
      purchaseRate: draft.purchaseRate,
    );
    ProductValidators.throwIfInvalid(errors);

    final code = draft.itemCode.trim();
    final dupCode = await db.findProductDuplicate(itemCode: code);
    if (dupCode != null) {
      throw ProductValidationException([
        'Duplicate Item Code — ${dupCode.itemCode}',
      ]);
    }
    final barcode = draft.barcode.trim();
    if (barcode.isNotEmpty) {
      final dupBc = await db.findProductDuplicate(barcode: barcode);
      if (dupBc != null) {
        throw ProductValidationException([
          'Duplicate Barcode — used by ${dupBc.itemCode}',
        ]);
      }
    }

    final now = DateTime.now();
    final model = ProductModel(
      id: newLocalId('item'),
      clientId: newClientId(),
      itemCode: code,
      itemName: draft.itemName.trim(),
      itemNameAr: _empty(draft.itemNameAr),
      itemGroup: draft.itemGroup.trim(),
      stockUom: draft.stockUom.trim(),
      salesUom: _empty(draft.salesUom) ?? draft.stockUom.trim(),
      description: _empty(draft.description),
      brand: _empty(draft.brand),
      barcode: _empty(draft.barcode),
      sku: _empty(draft.sku),
      hsCode: _empty(draft.hsCode),
      sellingRate: draft.sellingRate,
      purchaseRate: draft.purchaseRate,
      priceList: _empty(draft.priceList),
      taxTemplate: _empty(draft.taxTemplate),
      maintainStock: draft.maintainStock,
      disabled: draft.disabled,
      hasBatch: draft.hasBatch,
      hasSerial: draft.hasSerial,
      openingQuantity: draft.openingQuantity,
      openingWarehouse: _empty(draft.openingWarehouse),
      reorderLevel: draft.reorderLevel,
      weight: draft.weight,
      weightUom: _empty(draft.weightUom),
      incomeAccount: _empty(draft.incomeAccount),
      expenseAccount: _empty(draft.expenseAccount),
      costCenter: _empty(draft.costCenter),
      imagePath: draft.imagePath,
      galleryPaths: List.of(draft.galleryPaths),
      syncStatus: SyncStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    final database = await db.database;
    await database.transaction((txn) async {
      await db.upsertProduct(model, executor: txn);
      // Optimistic van stock for selling offline
      await db.upsertStockLine(
        StockLine(
          itemCode: model.itemCode,
          itemName: model.itemName,
          qty: model.openingQuantity > 0 ? model.openingQuantity : 0,
          uom: model.stockUom,
          unitPrice: model.sellingRate,
        ),
        executor: txn,
      );
      await db.enqueue(
        clientId: model.clientId,
        entityType: 'product',
        entityId: model.id,
        op: 'create',
        method: ProductApiMethods.sync,
        args: {'client_id': model.clientId, 'local_id': model.id},
        executor: txn,
      );
    });
    return model;
  }

  /// Update product locally (incl. images) and enqueue create/update.
  Future<ProductModel> updateLocal(
    String id,
    ProductDraft draft, {
    VanSaleSession? session,
  }) async {
    await VanSalePolicy.instance.assertCanMutate(session);
    final existing = await db.getProduct(id);
    if (existing == null) throw StateError('Product $id not found');
    draft.applyDefaults(_defaults);

    final errors = ProductValidators.validate(
      itemCode: draft.itemCode,
      itemName: draft.itemName,
      itemGroup: draft.itemGroup,
      stockUom: draft.stockUom,
      sellingRate: draft.sellingRate,
      purchaseRate: draft.purchaseRate,
    );
    ProductValidators.throwIfInvalid(errors);

    final code = draft.itemCode.trim();
    final dupCode = await db.findProductDuplicate(
      itemCode: code,
      excludeId: id,
    );
    if (dupCode != null) {
      throw ProductValidationException([
        'Duplicate Item Code — ${dupCode.itemCode}',
      ]);
    }
    final barcode = draft.barcode.trim();
    if (barcode.isNotEmpty) {
      final dupBc = await db.findProductDuplicate(
        barcode: barcode,
        excludeId: id,
      );
      if (dupBc != null) {
        throw ProductValidationException([
          'Duplicate Barcode — used by ${dupBc.itemCode}',
        ]);
      }
    }

    final neverSynced = existing.erpName == null || existing.erpName!.isEmpty;
    final now = DateTime.now();
    final model = ProductModel(
      id: existing.id,
      clientId: existing.clientId,
      itemCode: code,
      itemName: draft.itemName.trim(),
      itemNameAr: _empty(draft.itemNameAr),
      itemGroup: draft.itemGroup.trim(),
      stockUom: draft.stockUom.trim(),
      salesUom: _empty(draft.salesUom) ?? draft.stockUom.trim(),
      description: _empty(draft.description),
      brand: _empty(draft.brand),
      barcode: _empty(draft.barcode),
      sku: _empty(draft.sku),
      hsCode: _empty(draft.hsCode),
      sellingRate: draft.sellingRate,
      purchaseRate: draft.purchaseRate,
      priceList: _empty(draft.priceList),
      taxTemplate: _empty(draft.taxTemplate),
      maintainStock: draft.maintainStock,
      disabled: draft.disabled,
      hasBatch: draft.hasBatch,
      hasSerial: draft.hasSerial,
      openingQuantity: draft.openingQuantity,
      openingWarehouse: _empty(draft.openingWarehouse),
      reorderLevel: draft.reorderLevel,
      weight: draft.weight,
      weightUom: _empty(draft.weightUom),
      incomeAccount: _empty(draft.incomeAccount),
      expenseAccount: _empty(draft.expenseAccount),
      costCenter: _empty(draft.costCenter),
      imagePath: draft.imagePath ?? existing.imagePath,
      galleryPaths: draft.galleryPaths.isNotEmpty
          ? List.of(draft.galleryPaths)
          : existing.galleryPaths,
      syncStatus: SyncStatus.pending,
      erpName: existing.erpName,
      erpModified: existing.erpModified,
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    final op = neverSynced ? 'create' : 'update';
    final database = await db.database;
    await database.transaction((txn) async {
      await db.upsertProduct(model, executor: txn);
      await db.upsertStockLine(
        StockLine(
          itemCode: model.itemCode,
          itemName: model.itemName,
          qty:
              (await db.getStock(model.itemCode, executor: txn))?.qty ??
              model.openingQuantity,
          uom: model.stockUom,
          unitPrice: model.sellingRate,
        ),
        executor: txn,
      );
      await db.enqueue(
        clientId: model.clientId,
        entityType: 'product',
        entityId: model.id,
        op: op,
        method: ProductApiMethods.sync,
        args: {
          'client_id': model.clientId,
          'local_id': model.id,
          if (existing.erpModified != null)
            'base_modified': existing.erpModified,
        },
        conflict: ConflictAlgorithm.replace,
        executor: txn,
      );
    });
    return model;
  }

  /// Soft-delete (disable) on ERP when synced; otherwise remove local only.
  Future<void> deleteLocal(String id, {VanSaleSession? session}) async {
    await VanSalePolicy.instance.assertCanMutate(session);
    final existing = await db.getProduct(id);
    if (existing == null) return;
    final neverSynced = existing.erpName == null || existing.erpName!.isEmpty;
    final database = await db.database;
    if (neverSynced) {
      await database.transaction((txn) async {
        await db.clearQueueForEntity('product', id, executor: txn);
        await db.deleteProductRow(id, executor: txn);
      });
      return;
    }

    final model = ProductModel(
      id: existing.id,
      clientId: existing.clientId,
      itemCode: existing.itemCode,
      itemName: existing.itemName,
      itemNameAr: existing.itemNameAr,
      itemGroup: existing.itemGroup,
      stockUom: existing.stockUom,
      salesUom: existing.salesUom,
      description: existing.description,
      brand: existing.brand,
      barcode: existing.barcode,
      sku: existing.sku,
      hsCode: existing.hsCode,
      sellingRate: existing.sellingRate,
      purchaseRate: existing.purchaseRate,
      priceList: existing.priceList,
      taxTemplate: existing.taxTemplate,
      maintainStock: existing.maintainStock,
      disabled: true,
      hasBatch: existing.hasBatch,
      hasSerial: existing.hasSerial,
      openingQuantity: existing.openingQuantity,
      openingWarehouse: existing.openingWarehouse,
      reorderLevel: existing.reorderLevel,
      weight: existing.weight,
      weightUom: existing.weightUom,
      incomeAccount: existing.incomeAccount,
      expenseAccount: existing.expenseAccount,
      costCenter: existing.costCenter,
      imagePath: existing.imagePath,
      galleryPaths: existing.galleryPaths,
      syncStatus: SyncStatus.pending,
      erpName: existing.erpName,
      erpModified: existing.erpModified,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );

    await database.transaction((txn) async {
      await db.upsertProduct(model, executor: txn);
      await db.enqueue(
        clientId: model.clientId,
        entityType: 'product',
        entityId: model.id,
        op: 'delete',
        method: ProductApiMethods.sync,
        args: {
          'client_id': model.clientId,
          'local_id': model.id,
          if (existing.erpModified != null)
            'base_modified': existing.erpModified,
        },
        conflict: ConflictAlgorithm.replace,
        executor: txn,
      );
    });
  }

  Future<Map<String, dynamic>> buildSyncArgs(String localId) async {
    final model = await db.getProduct(localId);
    if (model == null) throw StateError('Product $localId not found');
    final company = VanSalePrefs.instance.company.trim();
    return mapper.toSyncArgs(
      model,
      company: company.isEmpty ? _defaults.company : company,
    );
  }

  String? extractErpName(Object? data) => mapper.extractErpName(data);

  String? _empty(String? v) => StringUtils.emptyToNull(v);
}

final productRepository = ProductRepository(VanSaleDb.instance);

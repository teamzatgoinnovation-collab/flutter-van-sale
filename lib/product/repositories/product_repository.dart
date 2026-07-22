import '../../data/van_sale_db.dart';
import '../../models/models.dart';
import '../../services/prefs.dart';
import '../../services/session.dart';
import '../mappers/product_sync_mapper.dart';
import '../models/product_model.dart';
import '../validation/product_validators.dart';

abstract final class ProductApiMethods {
  static const defaults = 'zatgo_core.api.v1.warehouse.items.defaults';
  static const sync = 'zatgo_core.api.v1.warehouse.items.sync';
  static const list = 'zatgo_core.api.v1.warehouse.items.list';
}

class ProductRepository {
  ProductRepository(
    this.db, {
    ProductSyncMapper mapper = const ProductSyncMapper(),
  }) : _mapper = mapper;

  final VanSaleDb db;
  final ProductSyncMapper _mapper;

  ProductDefaults _defaults = ProductDefaults.fallback();
  ProductDefaults get defaults => _defaults;

  Future<ProductDefaults> loadDefaults(VanSaleSession session) async {
    if (!session.connected) {
      _defaults = ProductDefaults.fallback();
      final wh = VanSalePrefs.instance.warehouse.trim();
      final company = VanSalePrefs.instance.company.trim();
      if (wh.isNotEmpty || company.isNotEmpty) {
        _defaults = ProductDefaults(
          itemGroup: _defaults.itemGroup,
          stockUom: _defaults.stockUom,
          salesUom: _defaults.salesUom,
          company: company,
          openingWarehouse: wh.isEmpty ? null : wh,
        );
      }
      return _defaults;
    }
    try {
      final env = await session.store.callMethod(ProductApiMethods.defaults);
      if (env.data is Map) {
        _defaults = ProductDefaults.fromJson(
          Map<String, dynamic>.from(env.data as Map),
        );
      }
    } catch (_) {}
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
    try {
      final env = await session.store.callMethod(
        ProductApiMethods.list,
        args: {'page': 1, 'page_size': 100},
      );
      final data = env.data;
      List rows = const [];
      if (data is List) {
        rows = data;
      } else if (data is Map && data['data'] is List) {
        rows = data['data'] as List;
      }
      var count = 0;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final code = '${map['item_code'] ?? map['id'] ?? map['name'] ?? ''}';
        if (code.isEmpty) continue;
        final existing = await db.getProductByCode(code);
        if (existing != null &&
            existing.syncStatus != SyncStatus.synced &&
            existing.erpName == null) {
          // Keep offline draft with same code
          continue;
        }
        final now = DateTime.now();
        await db.upsertProduct(
          ProductModel(
            id: existing?.id ?? 'erp_$code',
            clientId: existing?.clientId ?? 'erp_$code',
            itemCode: code,
            itemName: '${map['item_name'] ?? map['name'] ?? code}',
            itemGroup: '${map['item_group'] ?? _defaults.itemGroup}',
            stockUom: '${map['stock_uom'] ?? _defaults.stockUom}',
            sellingRate: (map['standard_rate'] as num?)?.toDouble() ??
                (map['rate'] as num?)?.toDouble() ??
                0,
            barcode: map['barcode'] == null ? null : '${map['barcode']}',
            maintainStock: true,
            disabled: (map['disabled'] as num?)?.toInt() == 1,
            syncStatus: SyncStatus.synced,
            erpName: code,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
        // Mirror into van_stock if missing (qty 0 until Bin pull)
        final stock = await db.getStock(code);
        if (stock == null) {
          await db.upsertStockLine(
            StockLine(
              itemCode: code,
              itemName: '${map['item_name'] ?? code}',
              qty: 0,
              uom: '${map['stock_uom'] ?? 'Nos'}',
              unitPrice: (map['standard_rate'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
        count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<List<ProductModel>> list({String? query}) =>
      db.listProducts(query: query);

  Future<ProductModel?> get(String id) => db.getProduct(id);

  Future<ProductModel> createLocal(ProductDraft draft) async {
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
      syncStatus: SyncStatus.queued,
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

  Future<Map<String, dynamic>> buildSyncArgs(String localId) async {
    final model = await db.getProduct(localId);
    if (model == null) throw StateError('Product $localId not found');
    final company = VanSalePrefs.instance.company.trim();
    return _mapper.toSyncArgs(
      model,
      company: company.isEmpty ? _defaults.company : company,
    );
  }

  String? extractErpName(Object? data) => _mapper.extractErpName(data);

  String? _empty(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

final productRepository = ProductRepository(VanSaleDb.instance);

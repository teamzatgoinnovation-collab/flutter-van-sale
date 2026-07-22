import '../../models/models.dart';

class ProductModel {
  const ProductModel({
    required this.id,
    required this.clientId,
    required this.itemCode,
    required this.itemName,
    required this.itemGroup,
    required this.stockUom,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
    this.itemNameAr,
    this.salesUom,
    this.description,
    this.brand,
    this.barcode,
    this.sku,
    this.hsCode,
    this.sellingRate = 0,
    this.purchaseRate = 0,
    this.priceList,
    this.taxTemplate,
    this.maintainStock = true,
    this.disabled = false,
    this.hasBatch = false,
    this.hasSerial = false,
    this.openingQuantity = 0,
    this.openingWarehouse,
    this.reorderLevel,
    this.weight,
    this.weightUom,
    this.incomeAccount,
    this.expenseAccount,
    this.costCenter,
    this.imagePath,
    this.galleryPaths = const [],
    this.erpName,
    this.erpModified,
    this.lastError,
  });

  final String id;
  final String clientId;
  final String itemCode;
  final String itemName;
  final String? itemNameAr;
  final String itemGroup;
  final String stockUom;
  final String? salesUom;
  final String? description;
  final String? brand;
  final String? barcode;
  final String? sku;
  final String? hsCode;

  final double sellingRate;
  final double purchaseRate;
  final String? priceList;
  final String? taxTemplate;

  final bool maintainStock;
  final bool disabled;
  final bool hasBatch;
  final bool hasSerial;
  final double openingQuantity;
  final String? openingWarehouse;
  final double? reorderLevel;
  final double? weight;
  final String? weightUom;

  final String? incomeAccount;
  final String? expenseAccount;
  final String? costCenter;

  final String? imagePath;
  final List<String> galleryPaths;

  final SyncStatus syncStatus;
  final String? erpName;
  /// Last known ERPNext `modified` — used for conflict detection.
  final String? erpModified;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayCode =>
      (erpName != null && erpName!.isNotEmpty) ? erpName! : itemCode;

  ProductModel copyWith({
    SyncStatus? syncStatus,
    String? erpName,
    String? erpModified,
    String? lastError,
  }) {
    return ProductModel(
      id: id,
      clientId: clientId,
      itemCode: itemCode,
      itemName: itemName,
      itemNameAr: itemNameAr,
      itemGroup: itemGroup,
      stockUom: stockUom,
      salesUom: salesUom,
      description: description,
      brand: brand,
      barcode: barcode,
      sku: sku,
      hsCode: hsCode,
      sellingRate: sellingRate,
      purchaseRate: purchaseRate,
      priceList: priceList,
      taxTemplate: taxTemplate,
      maintainStock: maintainStock,
      disabled: disabled,
      hasBatch: hasBatch,
      hasSerial: hasSerial,
      openingQuantity: openingQuantity,
      openingWarehouse: openingWarehouse,
      reorderLevel: reorderLevel,
      weight: weight,
      weightUom: weightUom,
      incomeAccount: incomeAccount,
      expenseAccount: expenseAccount,
      costCenter: costCenter,
      imagePath: imagePath,
      galleryPaths: galleryPaths,
      syncStatus: syncStatus ?? this.syncStatus,
      erpName: erpName ?? this.erpName,
      erpModified: erpModified ?? this.erpModified,
      lastError: lastError,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class ProductDefaults {
  const ProductDefaults({
    required this.itemGroup,
    required this.stockUom,
    required this.salesUom,
    required this.company,
    this.defaultPriceList,
    this.openingWarehouse,
    this.itemGroups = const [],
    this.uoms = const [],
    this.brands = const [],
    this.priceLists = const [],
    this.warehouses = const [],
    this.itemTaxTemplates = const [],
    this.incomeAccounts = const [],
    this.expenseAccounts = const [],
    this.costCenters = const [],
  });

  final String itemGroup;
  final String stockUom;
  final String salesUom;
  final String company;
  final String? defaultPriceList;
  final String? openingWarehouse;
  final List<String> itemGroups;
  final List<String> uoms;
  final List<String> brands;
  final List<String> priceLists;
  final List<String> warehouses;
  final List<String> itemTaxTemplates;
  final List<String> incomeAccounts;
  final List<String> expenseAccounts;
  final List<String> costCenters;

  factory ProductDefaults.fallback() => const ProductDefaults(
        itemGroup: 'Products',
        stockUom: 'Nos',
        salesUom: 'Nos',
        company: '',
      );

  factory ProductDefaults.fromJson(Map<String, dynamic> json) {
    List<String> list(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw.map((e) => '$e').where((e) => e.isNotEmpty).toList(growable: false);
    }

    return ProductDefaults(
      itemGroup: '${json['item_group'] ?? 'Products'}',
      stockUom: '${json['stock_uom'] ?? 'Nos'}',
      salesUom: '${json['sales_uom'] ?? json['stock_uom'] ?? 'Nos'}',
      company: '${json['company'] ?? ''}',
      defaultPriceList: json['default_price_list'] == null
          ? null
          : '${json['default_price_list']}',
      openingWarehouse: json['opening_warehouse'] == null
          ? null
          : '${json['opening_warehouse']}',
      itemGroups: list('item_groups'),
      uoms: list('uoms'),
      brands: list('brands'),
      priceLists: list('price_lists'),
      warehouses: list('warehouses'),
      itemTaxTemplates: list('item_tax_templates'),
      incomeAccounts: list('income_accounts'),
      expenseAccounts: list('expense_accounts'),
      costCenters: list('cost_centers'),
    );
  }
}

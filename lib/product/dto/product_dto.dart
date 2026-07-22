import '../models/product_model.dart';

class ProductDto {
  const ProductDto({
    required this.clientId,
    required this.itemCode,
    required this.itemName,
    required this.itemGroup,
    required this.stockUom,
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
    this.company,
    this.attachments = const {},
  });

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
  final String? company;
  final Map<String, dynamic> attachments;

  factory ProductDto.fromModel(
    ProductModel m, {
    String? company,
    Map<String, dynamic> attachments = const {},
  }) {
    return ProductDto(
      clientId: m.clientId,
      itemCode: m.itemCode,
      itemName: m.itemName,
      itemNameAr: m.itemNameAr,
      itemGroup: m.itemGroup,
      stockUom: m.stockUom,
      salesUom: m.salesUom,
      description: m.description,
      brand: m.brand,
      barcode: m.barcode,
      sku: m.sku,
      hsCode: m.hsCode,
      sellingRate: m.sellingRate,
      purchaseRate: m.purchaseRate,
      priceList: m.priceList,
      taxTemplate: m.taxTemplate,
      maintainStock: m.maintainStock,
      disabled: m.disabled,
      hasBatch: m.hasBatch,
      hasSerial: m.hasSerial,
      openingQuantity: m.openingQuantity,
      openingWarehouse: m.openingWarehouse,
      reorderLevel: m.reorderLevel,
      weight: m.weight,
      weightUom: m.weightUom,
      incomeAccount: m.incomeAccount,
      expenseAccount: m.expenseAccount,
      costCenter: m.costCenter,
      company: company,
      attachments: attachments,
    );
  }

  Map<String, dynamic> toItemJson() => {
        'item_code': itemCode,
        'item_name': itemName,
        if (itemNameAr != null && itemNameAr!.isNotEmpty)
          'item_name_ar': itemNameAr,
        'item_group': itemGroup,
        'stock_uom': stockUom,
        'sales_uom': salesUom ?? stockUom,
        'default_uom': salesUom ?? stockUom,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (brand != null && brand!.isNotEmpty) 'brand': brand,
        if (barcode != null && barcode!.isNotEmpty) 'barcode': barcode,
        if (sku != null && sku!.isNotEmpty) 'sku': sku,
        if (hsCode != null && hsCode!.isNotEmpty) 'hs_code': hsCode,
        'selling_rate': sellingRate,
        'purchase_rate': purchaseRate,
        if (priceList != null && priceList!.isNotEmpty) 'price_list': priceList,
        if (taxTemplate != null && taxTemplate!.isNotEmpty)
          'tax_template': taxTemplate,
        'is_stock_item': maintainStock ? 1 : 0,
        'maintain_stock': maintainStock ? 1 : 0,
        'disabled': disabled ? 1 : 0,
        'has_batch_no': hasBatch ? 1 : 0,
        'has_serial_no': hasSerial ? 1 : 0,
        if (openingQuantity > 0) 'opening_quantity': openingQuantity,
        if (openingWarehouse != null && openingWarehouse!.isNotEmpty)
          'opening_warehouse': openingWarehouse,
        if (reorderLevel != null) 'reorder_level': reorderLevel,
        if (weight != null) 'weight': weight,
        if (weightUom != null && weightUom!.isNotEmpty) 'weight_uom': weightUom,
        if (incomeAccount != null && incomeAccount!.isNotEmpty)
          'income_account': incomeAccount,
        if (expenseAccount != null && expenseAccount!.isNotEmpty)
          'expense_account': expenseAccount,
        if (costCenter != null && costCenter!.isNotEmpty)
          'cost_center': costCenter,
        if (company != null && company!.isNotEmpty) 'company': company,
      };
}

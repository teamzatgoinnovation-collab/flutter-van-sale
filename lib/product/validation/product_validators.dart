import '../models/product_model.dart';

class ProductValidationException implements Exception {
  ProductValidationException(this.errors);
  final List<String> errors;

  @override
  String toString() => errors.join('\n');
}

class ProductValidators {
  ProductValidators._();

  static List<String> validate({
    required String itemCode,
    required String itemName,
    required String itemGroup,
    required String stockUom,
    double? sellingRate,
    double? purchaseRate,
  }) {
    final errors = <String>[];
    if (itemCode.trim().isEmpty) errors.add('Item Code is required');
    if (itemName.trim().isEmpty) errors.add('Item Name is required');
    if (itemGroup.trim().isEmpty) errors.add('Item Group is required');
    if (stockUom.trim().isEmpty) errors.add('Stock UOM is required');
    if (sellingRate != null && sellingRate < 0) {
      errors.add('Selling Rate cannot be negative');
    }
    if (purchaseRate != null && purchaseRate < 0) {
      errors.add('Purchase Rate cannot be negative');
    }
    return errors;
  }

  static void throwIfInvalid(List<String> errors) {
    if (errors.isNotEmpty) throw ProductValidationException(errors);
  }
}

class ProductDraft {
  String itemCode = '';
  String itemName = '';
  String itemNameAr = '';
  String itemGroup = '';
  String stockUom = '';
  String salesUom = '';
  String description = '';
  String brand = '';
  String barcode = '';
  String sku = '';
  String hsCode = '';
  double sellingRate = 0;
  double purchaseRate = 0;
  String priceList = '';
  String taxTemplate = '';
  bool maintainStock = true;
  bool disabled = false;
  bool hasBatch = false;
  bool hasSerial = false;
  double openingQuantity = 0;
  String openingWarehouse = '';
  double? reorderLevel;
  double? weight;
  String weightUom = '';
  String incomeAccount = '';
  String expenseAccount = '';
  String costCenter = '';
  String? imagePath;
  List<String> galleryPaths = [];

  void applyDefaults(ProductDefaults d) {
    if (itemGroup.isEmpty) itemGroup = d.itemGroup;
    if (stockUom.isEmpty) stockUom = d.stockUom;
    if (salesUom.isEmpty) salesUom = d.salesUom;
    if (priceList.isEmpty && (d.defaultPriceList ?? '').isNotEmpty) {
      priceList = d.defaultPriceList!;
    }
    if (openingWarehouse.isEmpty && (d.openingWarehouse ?? '').isNotEmpty) {
      openingWarehouse = d.openingWarehouse!;
    }
  }
}

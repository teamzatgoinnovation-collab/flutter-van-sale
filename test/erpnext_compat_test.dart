import 'package:flutter_test/flutter_test.dart';
import 'package:van_sale/customer/mappers/customer_sync_mapper.dart';
import 'package:van_sale/customer/models/customer_model.dart';
import 'package:van_sale/customer/repositories/customer_repository.dart';
import 'package:van_sale/models/models.dart';
import 'package:van_sale/product/mappers/product_sync_mapper.dart';
import 'package:van_sale/product/models/product_model.dart';
import 'package:van_sale/product/repositories/product_repository.dart';

/// Contract tests: ERPNext v16 / ZatGoCore method paths + sync payload shape.
void main() {
  test('customer API methods target accounting.customers', () {
    expect(CustomerApiMethods.defaults, contains('accounting.customers.defaults'));
    expect(CustomerApiMethods.sync, contains('accounting.customers.sync'));
    expect(CustomerApiMethods.list, contains('accounting.customers.list'));
    expect(CustomerApiMethods.sync, startsWith('zatgo_core.api.v1.'));
  });

  test('product API methods target warehouse.items', () {
    expect(ProductApiMethods.defaults, contains('warehouse.items.defaults'));
    expect(ProductApiMethods.sync, contains('warehouse.items.sync'));
    expect(ProductApiMethods.list, contains('warehouse.items.list'));
    expect(ProductApiMethods.sync, startsWith('zatgo_core.api.v1.'));
  });

  test('customer sync payload has client_id + customer/contact/address', () async {
    final now = DateTime.now();
    final model = CustomerModel(
      id: 'local_1',
      clientId: 'cid-1',
      customerName: 'Acme',
      customerType: 'Company',
      customerGroup: 'Commercial',
      territory: 'Saudi Arabia',
      mobileNo: '0500000000',
      addressLine1: 'St 1',
      city: 'Riyadh',
      country: 'Saudi Arabia',
      syncStatus: SyncStatus.pending,
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );
    final args = await const CustomerSyncMapper().toSyncArgs(model);
    expect(args['client_id'], 'cid-1');
    expect(args['customer'], isA<Map>());
    expect(args['contact'], isA<Map>());
    expect(args['address'], isA<Map>());
    final customer = args['customer'] as Map;
    expect(customer['customer_name'], 'Acme');
    expect(customer.containsKey('customer_group'), isTrue);
  });

  test('product sync payload has client_id + item', () async {
    final now = DateTime.now();
    final model = ProductModel(
      id: 'local_p',
      clientId: 'pid-1',
      itemCode: 'SKU-1',
      itemName: 'Widget',
      itemGroup: 'Products',
      stockUom: 'Nos',
      sellingRate: 10,
      syncStatus: SyncStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    final args = await const ProductSyncMapper().toSyncArgs(model);
    expect(args['client_id'], 'pid-1');
    expect(args['item'], isA<Map>());
    final item = args['item'] as Map;
    expect(item['item_code'], 'SKU-1');
    expect(item['item_name'], 'Widget');
    expect(item.containsKey('stock_uom'), isTrue);
  });

  test('ERP name extraction matches ERPNext name fields', () {
    expect(
      const CustomerSyncMapper().extractErpName({'name': 'CUST-01'}),
      'CUST-01',
    );
    expect(
      const ProductSyncMapper().extractErpName({'item_code': 'ITEM-01'}),
      'ITEM-01',
    );
  });
}

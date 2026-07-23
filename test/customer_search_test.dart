import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/customer/models/customer_model.dart';
import 'package:van_sale/customer/repositories/customer_repository.dart';
import 'package:van_sale/customer/validation/customer_validators.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/services/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await VanSalePrefs.instance.resetForTest();
    await VanSalePrefs.instance.setWorkMode(VanSaleWorkMode.onlineOffline);
    final db = await VanSaleDb.instance.database;
    await db.delete('sync_queue');
    await db.delete('customer_favorites');
    await db.delete('customer_recent');
    await db.delete('customers');
  });

  Future<CustomerModel> seed({
    required String name,
    String? nameAr,
    String mobile = '0500000001',
    String? vat,
    String? cr,
    String? code,
    String? email,
    String? barcode,
  }) {
    return customerRepository.createLocal(
      CustomerDraft()
        ..customerName = name
        ..customerNameAr = nameAr ?? ''
        ..customerGroup = 'Commercial'
        ..territory = 'Saudi Arabia'
        ..mobileNo = mobile
        ..taxId = vat ?? ''
        ..crNumber = cr ?? ''
        ..customerCode = code ?? ''
        ..email = email ?? ''
        ..barcode = barcode ?? ''
        ..addressLine1 = 'St'
        ..city = 'Riyadh'
        ..country = 'Saudi Arabia',
    );
  }

  test('search matches name, arabic, phone, vat, cr, code, email', () async {
    await seed(name: 'Alpha Co', nameAr: 'الفا', mobile: '0501111111');
    await seed(
      name: 'Beta LLC',
      mobile: '0502222222',
      vat: '300000000000003',
      cr: 'CR-99',
      code: 'C-BETA',
      email: 'beta@example.com',
    );

    expect(
      (await customerRepository.search(query: 'الفا')).items.first.customerName,
      'Alpha Co',
    );
    expect(
      (await customerRepository.search(query: '050222')).items.first.customerName,
      'Beta LLC',
    );
    expect(
      (await customerRepository.search(query: '300000000000003'))
          .items
          .first
          .customerName,
      'Beta LLC',
    );
    expect(
      (await customerRepository.search(query: 'CR-99')).items.first.customerName,
      'Beta LLC',
    );
    expect(
      (await customerRepository.search(query: 'C-BETA')).items.first.customerName,
      'Beta LLC',
    );
    expect(
      (await customerRepository.search(query: 'beta@example'))
          .items
          .first
          .customerName,
      'Beta LLC',
    );
  });

  test('barcode exact + favorites + recent + pagination', () async {
    final a = await seed(name: 'A', mobile: '0501000001', barcode: 'BC-A');
    final b = await seed(name: 'B', mobile: '0501000002', barcode: 'BC-B');
    for (var i = 0; i < 35; i++) {
      await seed(name: 'Bulk $i', mobile: '051${i.toString().padLeft(7, '0')}');
    }

    expect((await customerRepository.findByBarcode('BC-A'))?.id, a.id);

    await customerRepository.toggleFavorite(b.id, favorite: true);
    final favs = await customerRepository.search(
      scope: CustomerSearchScope.favorites,
    );
    expect(favs.items.map((e) => e.id), contains(b.id));

    await customerRepository.markRecent(a.id);
    final recent = await customerRepository.search(
      scope: CustomerSearchScope.recent,
    );
    expect(recent.items.first.id, a.id);

    final page1 = await customerRepository.search(limit: 10, offset: 0);
    expect(page1.items.length, 10);
    expect(page1.hasMore, isTrue);
    final page2 = await customerRepository.search(limit: 10, offset: 10);
    expect(page2.items.length, 10);
    expect(page1.items.first.id, isNot(page2.items.first.id));
  });
}

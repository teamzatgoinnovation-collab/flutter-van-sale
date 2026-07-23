import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/customer/repositories/customer_repository.dart';
import 'package:van_sale/customer/validation/customer_validators.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/models/models.dart';
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
    await db.delete('customers');
  });

  test('customer validators require core fields', () {
    final errors = CustomerValidators.validate(
      customerName: '',
      mobileNo: '',
      addressLine1: '',
      city: '',
      country: '',
      customerGroup: '',
      territory: '',
    );
    expect(errors, isNotEmpty);
  });

  test('createLocal enqueues customer sync with client_id', () async {
    final repo = CustomerRepository(VanSaleDb.instance);
    final draft = CustomerDraft()
      ..customerName = 'Test Co'
      ..customerType = 'Company'
      ..customerGroup = 'Commercial'
      ..territory = 'Saudi Arabia'
      ..mobileNo = '0501234567'
      ..addressLine1 = 'King Fahd Rd'
      ..city = 'Riyadh'
      ..country = 'Saudi Arabia';

    final created = await repo.createLocal(draft);
    expect(created.syncStatus, SyncStatus.pending);
    expect(created.clientId, isNotEmpty);

    final queue = await VanSaleDb.instance.peekQueue();
    expect(queue.any((q) => q.entityType == 'customer'), isTrue);
    final item = queue.firstWhere((q) => q.entityType == 'customer');
    expect(item.clientId, created.clientId);
    expect(item.method, contains('customers.sync'));
  });

  test('duplicate mobile rejected locally', () async {
    final repo = CustomerRepository(VanSaleDb.instance);
    Future<void> make(String name) async {
      final draft = CustomerDraft()
        ..customerName = name
        ..customerGroup = 'Commercial'
        ..territory = 'Saudi Arabia'
        ..mobileNo = '0509998877'
        ..addressLine1 = 'St 1'
        ..city = 'Jeddah'
        ..country = 'Saudi Arabia';
      await repo.createLocal(draft);
    }

    await make('First');
    expect(() => make('Second'), throwsA(isA<CustomerValidationException>()));
  });
}

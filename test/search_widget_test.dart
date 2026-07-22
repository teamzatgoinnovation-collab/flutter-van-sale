import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:van_sale/customer/pages/customer_search_page.dart';
import 'package:van_sale/data/van_sale_db.dart';
import 'package:van_sale/pages/sell_order_page.dart';
import 'package:van_sale/product/pages/product_search_page.dart';
import 'package:van_sale/services/prefs.dart';
import 'package:van_sale/services/session.dart';
import 'package:van_sale/services/sync_service.dart';

/// Widget smoke tests (no isolate wait): list/search coverage lives in
/// customer_search_test / product_search_test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await VanSalePrefs.instance.resetForTest();
    final db = await VanSaleDb.instance.database;
    await db.delete('sync_queue');
    await db.delete('customers');
    await db.delete('products');
  });

  testWidgets('CustomerSearchPage builds offline shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerSearchPage(
          session: VanSaleSession(),
          selectMode: false,
        ),
      ),
    );
    expect(find.text('Customers'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner_outlined), findsOneWidget);
  });

  testWidgets('CustomerSearchPage selectMode title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerSearchPage(
          session: VanSaleSession(),
          selectMode: true,
        ),
      ),
    );
    expect(find.text('Select customer'), findsOneWidget);
  });

  testWidgets('ProductSearchPage builds offline shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProductSearchPage(
          session: VanSaleSession(),
          selectMode: false,
        ),
      ),
    );
    expect(find.text('Products'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('SellOrderPage builds cart shell', (tester) async {
    final session = VanSaleSession();
    await tester.pumpWidget(
      MaterialApp(
        home: SellOrderPage(
          session: session,
          sync: SyncService(session),
        ),
      ),
    );
    expect(find.text('New sale'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(); // start bootstrap future
  });
}

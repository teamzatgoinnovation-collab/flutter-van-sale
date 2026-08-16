import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:van_sale/pages/login_page.dart';
import 'package:van_sale/services/prefs.dart';
import 'package:van_sale/services/session.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await VanSalePrefs.instance.init();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('VanSale Auto Test Login Tests', () {
    test('VanSaleSession initializes default site URL and authed state', () {
      final session = VanSaleSession();
      expect(session.baseUrl, contains('zatgo.online'));
      expect(session.connected, false);
      expect(session.user, isNull);
      expect(session.fullName, isNull);
      expect(session.lastError, isNull);
      expect(session.hasVansaleAccess, false);
    });

    testWidgets('LoginPage renders input fields, site URL, and Sign in button', (
      WidgetTester tester,
    ) async {
      final session = VanSaleSession();
      bool authedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            session: session,
            onAuthed: () {
              authedCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Sign in'), findsOneWidget);
      expect(authedCalled, false);
    });

    testWidgets('LoginPage updates username and password input text', (
      WidgetTester tester,
    ) async {
      final session = VanSaleSession();

      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            session: session,
            onAuthed: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Administrator');
      await tester.enterText(textFields.at(1), 'admin');
      await tester.pumpAndSettle();

      expect(find.text('Administrator'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
    });

    testWidgets('LoginPage displays accessMessage banner when provided', (
      WidgetTester tester,
    ) async {
      final session = VanSaleSession();
      const testMsg = 'Access Denied: No VanSale role found.';

      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            session: session,
            onAuthed: () {},
            accessMessage: testMsg,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(testMsg), findsOneWidget);
    });

    test('persisted session survives a fresh VanSaleSession instance (simulated app restart)', () async {
      final original = VanSaleSession();
      original.store.restoreSession(
        baseUrl: 'https://vansale.zatgo.online',
        sidCookie: 'sid=abc123',
      );
      original.user = 'driver@zatgo.online';
      original.fullName = 'Test Driver';
      await original.persistSession();

      // A brand-new instance (as if the app process was killed and relaunched
      // offline) must be able to restore straight to an authed state.
      final restarted = VanSaleSession();
      expect(restarted.connected, false);
      final restored = await restarted.restoreSessionFromStorage();

      expect(restored, true);
      expect(restarted.connected, true);
      expect(restarted.baseUrl, 'https://vansale.zatgo.online');
      expect(restarted.user, 'driver@zatgo.online');
      expect(restarted.fullName, 'Test Driver');
      expect(restarted.restoredFromStorage, true);
      expect(restarted.store.sidCookie, 'sid=abc123');
    });

    test('logout clears the persisted session so restart requires a fresh login', () async {
      final session = VanSaleSession();
      session.store.restoreSession(
        baseUrl: 'https://vansale.zatgo.online',
        sidCookie: 'sid=xyz789',
      );
      await session.persistSession();
      await session.logout();

      final restarted = VanSaleSession();
      final restored = await restarted.restoreSessionFromStorage();
      expect(restored, false);
      expect(restarted.connected, false);
    });

    test('restoreSessionFromStorage returns false when nothing was persisted', () async {
      final session = VanSaleSession();
      final restored = await session.restoreSessionFromStorage();
      expect(restored, false);
      expect(session.connected, false);
      expect(session.restoredFromStorage, false);
    });
  });
}

import 'package:flutter/material.dart';
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

      expect(find.text('ZatGo'), findsOneWidget);
      expect(find.text('VanSale'), findsOneWidget);
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
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sale/pages/admin_shell.dart';
import 'package:van_sale/services/session.dart';
import 'package:van_sale/services/van_sale_context.dart';

void main() {
  group('VanSaleContext', () {
    test('parses admin + profile', () {
      final ctx = VanSaleContext.fromJson({
        'user': 'admin@zatgo.online',
        'full_name': 'Admin',
        'roles': ['VanSale Admin', 'System Manager'],
        'is_admin': true,
        'is_user': false,
        'has_vansale_access': true,
        'profile': null,
      });
      expect(ctx.isAdmin, isTrue);
      expect(ctx.isUser, isFalse);
      expect(ctx.hasVansaleAccess, isTrue);
    });

    test('parses field user + warehouse profile', () {
      final ctx = VanSaleContext.fromJson({
        'user': 'van1@zatgo.online',
        'full_name': 'Van One',
        'roles': ['VanSale User'],
        'is_admin': false,
        'is_user': true,
        'has_vansale_access': true,
        'profile': {
          'id': 'PROF-1',
          'user': 'van1@zatgo.online',
          'warehouse': 'Van-01',
          'vehicle': 'VH-01',
          'route_title': 'North',
          'enabled': 1,
        },
      });
      expect(ctx.isUser, isTrue);
      expect(ctx.profile?.warehouse, 'Van-01');
      expect(ctx.profile?.routeTitle, 'North');
    });
  });

  group('VanSaleSession shell mode', () {
    test('admin without user role stays on admin shell', () {
      final session = VanSaleSession();
      session.context = VanSaleContext.fromJson({
        'user': 'a@x.com',
        'full_name': 'A',
        'roles': ['VanSale Admin'],
        'is_admin': true,
        'is_user': false,
        'has_vansale_access': true,
      });
      session.preferUserMode = true;
      expect(session.showAdminShell, isTrue);
    });

    test('admin+user can switch to my van', () {
      final session = VanSaleSession();
      session.context = VanSaleContext.fromJson({
        'user': 'a@x.com',
        'full_name': 'A',
        'roles': ['VanSale Admin', 'VanSale User'],
        'is_admin': true,
        'is_user': true,
        'has_vansale_access': true,
      });
      expect(session.showAdminShell, isTrue);
      session.setPreferUserMode(true);
      expect(session.showAdminShell, isFalse);
      session.setPreferUserMode(false);
      expect(session.showAdminShell, isTrue);
    });
  });

  testWidgets('AdminFilterBar builds', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final filters = AdminFilterState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminFilterBar(
            filters: filters,
            profiles: const [
              VanSaleProfile(
                id: '1',
                user: 'van1@zatgo.online',
                warehouse: 'Van-01',
                vehicle: 'VH-01',
                routeTitle: 'North',
              ),
            ],
            onChanged: () {},
          ),
        ),
      ),
    );
    expect(find.text('User'), findsOneWidget);
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Vehicle'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';

import '../services/auth_scope.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import 'collections_page.dart';
import 'connection_page.dart';
import 'orders_page.dart';
import 'stock_page.dart';
import 'today_page.dart';

class VanSaleShell extends StatefulWidget {
  const VanSaleShell({
    super.key,
    required this.session,
    required this.sync,
    this.onRequireLogin,
  });

  final VanSaleSession session;
  final SyncService sync;
  final VoidCallback? onRequireLogin;

  @override
  State<VanSaleShell> createState() => _VanSaleShellState();
}

class _VanSaleShellState extends State<VanSaleShell> {
  int _index = 0;
  String? _prefillCustomer;

  Future<void> _signOut() async {
    await widget.session.logout();
    widget.onRequireLogin?.call();
  }

  void _openSell({String? customer}) {
    setState(() {
      _prefillCustomer = customer;
      _index = 1;
    });
  }

  void _openCash({String? customer}) {
    setState(() {
      _prefillCustomer = customer;
      _index = 2;
    });
  }

  void _clearPrefill() {
    if (_prefillCustomer != null) {
      setState(() => _prefillCustomer = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(
        sync: widget.sync,
        onSell: (customer) => _openSell(customer: customer),
        onCollect: (customer) => _openCash(customer: customer),
      ),
      OrdersPage(
        sync: widget.sync,
        initialCustomer: _index == 1 ? _prefillCustomer : null,
        onConsumedPrefill: _clearPrefill,
      ),
      CollectionsPage(
        sync: widget.sync,
        initialCustomer: _index == 2 ? _prefillCustomer : null,
        onConsumedPrefill: _clearPrefill,
      ),
      StockPage(sync: widget.sync),
      ConnectionPage(
        session: widget.session,
        sync: widget.sync,
        onSignOut: _signOut,
      ),
    ];

    return VanSaleAuthScope(
      session: widget.session,
      onSignOut: _signOut,
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          height: 72,
          elevation: 0,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined),
              selectedIcon: Icon(Icons.point_of_sale),
              label: 'Sell',
            ),
            NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments),
              label: 'Cash',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Stock',
            ),
            NavigationDestination(
              icon: Icon(Icons.link_outlined),
              selectedIcon: Icon(Icons.link),
              label: 'Link',
            ),
          ],
        ),
      ),
    );
  }
}

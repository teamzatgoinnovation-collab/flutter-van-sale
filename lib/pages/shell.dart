import 'package:flutter/material.dart';

import '../services/auth_scope.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import 'collections_page.dart';
import 'orders_page.dart';
import 'settings_page.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsPage(session: widget.session, sync: widget.sync),
      ),
    );
  }

  Future<void> _syncNow() async {
    final result = await widget.sync.flush();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Synced ${result.processed} · failed ${result.failed}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(
        sync: widget.sync,
        onSell: (customer) => _openSell(customer: customer),
        onCollect: (customer) => _openCash(customer: customer),
        onOpenMenu: _openDrawer,
      ),
      OrdersPage(
        sync: widget.sync,
        initialCustomer: _index == 1 ? _prefillCustomer : null,
        onConsumedPrefill: _clearPrefill,
        onOpenMenu: _openDrawer,
      ),
      CollectionsPage(
        sync: widget.sync,
        initialCustomer: _index == 2 ? _prefillCustomer : null,
        onConsumedPrefill: _clearPrefill,
        onOpenMenu: _openDrawer,
      ),
      StockPage(sync: widget.sync, onOpenMenu: _openDrawer),
    ];

    final user = widget.session.fullName ?? widget.session.user ?? 'User';

    return VanSaleAuthScope(
      session: widget.session,
      onSignOut: _signOut,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VanSale',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(user, style: Theme.of(context).textTheme.bodyMedium),
                      Text(
                        widget.session.baseUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () {
                    Navigator.pop(context);
                    _openSettings();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: const Text('Sync now'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _syncNow();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _signOut();
                  },
                ),
              ],
            ),
          ),
        ),
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
          ],
        ),
      ),
    );
  }
}

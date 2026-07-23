import 'package:flutter/material.dart';

import '../services/session.dart';
import '../services/sync_service.dart';
import '../services/van_sale_admin_api.dart';
import '../services/van_sale_context.dart';
import 'admin_cash_page.dart';
import 'admin_overview_page.dart';
import 'admin_routes_page.dart';
import 'admin_sales_page.dart';
import 'settings_page.dart';

class AdminFilterState {
  String? salesUser;
  String? warehouse;
  String? vehicle;
  String? routeTitle;
}

/// Admin monitor shell: Overview · Routes · Sales · Cash.
class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.session,
    required this.sync,
    this.onRequireLogin,
  });

  final VanSaleSession session;
  final SyncService sync;
  final VoidCallback? onRequireLogin;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  final _filters = AdminFilterState();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final VanSaleAdminApi _api;
  List<VanSaleProfile> _profiles = const [];

  @override
  void initState() {
    super.initState();
    _api = VanSaleAdminApi(widget.session);
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final rows = await _api.listUsers();
      if (!mounted) return;
      setState(() => _profiles = rows);
    } catch (_) {}
  }

  Future<void> _signOut() async {
    await widget.session.logout();
    widget.onRequireLogin?.call();
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

  @override
  Widget build(BuildContext context) {
    final user = widget.session.fullName ?? widget.session.user ?? 'Admin';
    final pages = [
      AdminOverviewPage(
        api: _api,
        filters: _filters,
        profiles: _profiles,
        onFiltersChanged: () => setState(() {}),
        onOpenMenu: _openDrawer,
      ),
      AdminRoutesPage(
        api: _api,
        filters: _filters,
        profiles: _profiles,
        onFiltersChanged: () => setState(() {}),
        onOpenMenu: _openDrawer,
      ),
      AdminSalesPage(
        api: _api,
        filters: _filters,
        profiles: _profiles,
        onFiltersChanged: () => setState(() {}),
        onOpenMenu: _openDrawer,
      ),
      AdminCashPage(
        api: _api,
        filters: _filters,
        profiles: _profiles,
        onFiltersChanged: () => setState(() {}),
        onOpenMenu: _openDrawer,
      ),
    ];

    return Scaffold(
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
                      'VanSale Admin',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(user),
                    Text(
                      widget.session.baseUrl,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.session.isFieldUser)
                ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: const Text('My van'),
                  subtitle: const Text('Switch to field mode'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.session.setPreferUserMode(true);
                  },
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
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Routes',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Cash',
          ),
        ],
      ),
    );
  }
}

/// Shared filter chips for admin pages.
class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    super.key,
    required this.filters,
    required this.profiles,
    required this.onChanged,
  });

  final AdminFilterState filters;
  final List<VanSaleProfile> profiles;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final users = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(value: null, child: Text('All users')),
      for (final p in profiles)
        DropdownMenuItem(
          value: p.user,
          child: Text(p.user.split('@').first),
        ),
    ];
    final routes = <String>{
      for (final p in profiles)
        if ((p.routeTitle ?? '').isNotEmpty) p.routeTitle!,
    }.toList()
      ..sort();
    final vehicles = <String>{
      for (final p in profiles)
        if ((p.vehicle ?? '').isNotEmpty) p.vehicle!,
    }.toList()
      ..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('admin-user-${filters.salesUser}'),
              initialValue: filters.salesUser,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'User',
                isDense: true,
              ),
              items: users,
              onChanged: (v) {
                filters.salesUser = v;
                final match = profiles.where((p) => p.user == v).toList();
                if (match.isNotEmpty) {
                  filters.warehouse = match.first.warehouse;
                  filters.vehicle = match.first.vehicle;
                  filters.routeTitle = match.first.routeTitle;
                } else if (v == null) {
                  filters.warehouse = null;
                  filters.vehicle = null;
                  filters.routeTitle = null;
                }
                onChanged();
              },
            ),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String?>(
              key: ValueKey(
                'admin-route-${filters.salesUser}-${filters.routeTitle}',
              ),
              initialValue: filters.routeTitle,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Route',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All routes')),
                for (final r in routes)
                  DropdownMenuItem(value: r, child: Text(r)),
              ],
              onChanged: (v) {
                filters.routeTitle = v;
                onChanged();
              },
            ),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String?>(
              key: ValueKey(
                'admin-vehicle-${filters.salesUser}-${filters.vehicle}',
              ),
              initialValue: filters.vehicle,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Vehicle',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All vehicles'),
                ),
                for (final v in vehicles)
                  DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: (v) {
                filters.vehicle = v;
                onChanged();
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/van_sale_admin_api.dart';
import '../services/van_sale_context.dart';
import '../widgets/widgets.dart';
import 'admin_shell.dart';

class AdminOverviewPage extends StatefulWidget {
  const AdminOverviewPage({
    super.key,
    required this.api,
    required this.filters,
    required this.profiles,
    required this.onFiltersChanged,
    this.onOpenMenu,
  });

  final VanSaleAdminApi api;
  final AdminFilterState filters;
  final List<VanSaleProfile> profiles;
  final VoidCallback onFiltersChanged;
  final VoidCallback? onOpenMenu;

  @override
  State<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends State<AdminOverviewPage> {
  Map<String, dynamic>? _summary;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters.salesUser != widget.filters.salesUser ||
        oldWidget.filters.routeTitle != widget.filters.routeTitle ||
        oldWidget.filters.vehicle != widget.filters.vehicle) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.summary(
        salesUser: widget.filters.salesUser,
        warehouse: widget.filters.warehouse,
        vehicle: widget.filters.vehicle,
        routeTitle: widget.filters.routeTitle,
      );
      if (!mounted) return;
      setState(() {
        _summary = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _summary;
    final byUser = (s?['by_user'] is List) ? s!['by_user'] as List : const [];

    return PageScaffold(
      title: 'Overview',
      subtitle: 'All vans · today',
      onOpenMenu: widget.onOpenMenu,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        children: [
          AdminFilterBar(
            filters: widget.filters,
            profiles: widget.profiles,
            onChanged: () {
              widget.onFiltersChanged();
              _load();
            },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.25,
                          children: [
                            KpiCard(
                              title: 'Stops done',
                              value:
                                  '${s?['stops_done'] ?? 0}/${s?['stops_total'] ?? 0}',
                              icon: Icons.route_outlined,
                              accentColor: const Color(0xFF0F4C5C),
                            ),
                            KpiCard(
                              title: 'Sales total',
                              value: money(
                                (s?['sales_total'] as num?)?.toDouble() ?? 0,
                              ),
                              icon: Icons.point_of_sale_outlined,
                              accentColor: const Color(0xFFE36414),
                            ),
                            KpiCard(
                              title: 'Collections',
                              value: money(
                                (s?['collections_total'] as num?)
                                        ?.toDouble() ??
                                    0,
                              ),
                              icon: Icons.payments_outlined,
                              accentColor: const Color(0xFF2A9D8F),
                            ),
                            KpiCard(
                              title: 'Total orders',
                              value: '${s?['orders_count'] ?? 0}',
                              icon: Icons.receipt_long_outlined,
                              accentColor: Colors.indigo,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'By user',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (byUser.isEmpty)
                          const EmptyHint('No activity today')
                        else
                          ...byUser.map((raw) {
                            final u = Map<String, dynamic>.from(raw as Map);
                            return Card(
                              child: ListTile(
                                title: Text(
                                  '${u['full_name'] ?? u['user']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  'Stops ${u['stops_done']}/${u['stops_total']} · '
                                  'Orders ${u['orders_count']}',
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      money(
                                        (u['sales_total'] as num?)
                                                ?.toDouble() ??
                                            0,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      money(
                                        (u['collections_total'] as num?)
                                                ?.toDouble() ??
                                            0,
                                      ),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

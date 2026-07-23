import 'package:flutter/material.dart';

import '../services/van_sale_admin_api.dart';
import '../services/van_sale_context.dart';
import '../widgets/widgets.dart';
import 'admin_shell.dart';

class AdminRoutesPage extends StatefulWidget {
  const AdminRoutesPage({
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
  State<AdminRoutesPage> createState() => _AdminRoutesPageState();
}

class _AdminRoutesPageState extends State<AdminRoutesPage> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminRoutesPage oldWidget) {
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
      final rows = await widget.api.listTrips(
        salesUser: widget.filters.salesUser,
        warehouse: widget.filters.warehouse,
        vehicle: widget.filters.vehicle,
        routeTitle: widget.filters.routeTitle,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
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
    return PageScaffold(
      title: 'Routes',
      subtitle: 'Stops across vans',
      onOpenMenu: widget.onOpenMenu,
      actions: [
        IconButton(
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
                : _rows.isEmpty
                ? const EmptyHint('No stops match filters')
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: KpiCard(
                                title: 'Total Stops',
                                value: '${_rows.length}',
                                icon: Icons.map_outlined,
                                accentColor: const Color(0xFF0F4C5C),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: KpiCard(
                                title: 'Visited',
                                value: '${_rows.where((r) => '${r['status']}'.toLowerCase() == 'completed' || '${r['status']}'.toLowerCase() == 'checked in').length}',
                                icon: Icons.check_circle_outline,
                                accentColor: const Color(0xFF2A9D8F),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ..._rows.map((r) {
                          final status = '${r['status'] ?? 'planned'}'.toLowerCase();
                          final (statusLabel, statusColor) = switch (status) {
                            'checked in' => ('Checked in', const Color(0xFFE36414)),
                            'completed' => ('Completed', const Color(0xFF0F4C5C)),
                            'skipped' => ('Skipped', Colors.brown),
                            _ => ('Planned', Colors.blueGrey),
                          };

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: statusColor.withValues(alpha: 0.15),
                                        child: Text(
                                          '${r['sequence'] ?? '#'}',
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${r['customer'] ?? r['title'] ?? 'Stop'}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: statusColor.withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${r['address'] ?? 'No address'}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.person_outline,
                                        size: 14,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${r['sales_user'] ?? '—'} · ${r['route_title'] ?? '—'}',
                                        style: Theme.of(context).textTheme.labelSmall,
                                      ),
                                    ],
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

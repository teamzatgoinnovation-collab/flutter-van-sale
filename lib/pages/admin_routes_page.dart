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
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        return Card(
                          child: ListTile(
                            title: Text(
                              '${r['customer'] ?? r['title'] ?? 'Stop'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${r['address'] ?? ''}\n'
                              '${r['sales_user'] ?? ''} · ${r['route_title'] ?? ''} · '
                              '${r['status'] ?? ''}',
                            ),
                            isThreeLine: true,
                            trailing: Text('#${r['sequence'] ?? ''}'),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

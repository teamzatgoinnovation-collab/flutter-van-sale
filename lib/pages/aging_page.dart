import 'package:flutter/material.dart';

import '../services/aging_service.dart';
import '../services/session.dart';
import '../widgets/aging_summary_card.dart';
import '../widgets/widgets.dart';

class AgingPage extends StatefulWidget {
  const AgingPage({super.key, required this.session, this.customer});

  final VanSaleSession session;
  final String? customer;

  @override
  State<AgingPage> createState() => _AgingPageState();
}

class _AgingPageState extends State<AgingPage> {
  late final AgingService _api = AgingService(widget.session);
  AgingSummary? _summary;
  List<Map<String, dynamic>> _invoices = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _api.summary(customer: widget.customer);
      List<Map<String, dynamic>> invoices = const [];
      try {
        invoices = await _api.detail(customer: widget.customer);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _invoices = invoices;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.customer == null || widget.customer!.isEmpty
              ? 'Receivables aging'
              : 'Aging · ${widget.customer}',
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _summary == null
          ? EmptyHint(_error!, icon: Icons.error_outline)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (_summary != null)
                  AgingSummaryCard(summary: _summary!, onOpenDetail: null),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Open invoices',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_invoices.isEmpty)
                  const EmptyHint(
                    'No open invoices in this view',
                    icon: Icons.receipt_long_outlined,
                  )
                else
                  ..._invoices.map((inv) {
                    final name = '${inv['name'] ?? ''}';
                    final party =
                        '${inv['customer_name'] ?? inv['customer'] ?? ''}';
                    final outstanding =
                        (inv['outstanding_amount'] as num?)?.toDouble() ?? 0;
                    final due =
                        '${inv['due_date'] ?? inv['posting_date'] ?? ''}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('$party · due $due'),
                        trailing: Text(
                          money(outstanding),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    );
                  }),
                if ((_summary?.customers.isNotEmpty ?? false) &&
                    (widget.customer == null || widget.customer!.isEmpty)) ...[
                  const SizedBox(height: 16),
                  Text(
                    'By customer',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._summary!.customers.take(40).map((c) {
                    final name = '${c['customer_name'] ?? c['customer'] ?? ''}';
                    final overdue = (c['overdue'] as num?)?.toDouble() ?? 0;
                    final total = (c['total'] as num?)?.toDouble() ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(name),
                        subtitle: Text(
                          'Overdue ${money(overdue)} · total ${money(total)}',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AgingPage(
                                session: widget.session,
                                customer: '${c['customer'] ?? ''}',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';

import '../customer/models/customer_model.dart';
import '../customer/pages/customer_search_page.dart';
import '../customer/repositories/customer_repository.dart';
import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../services/auth_scope.dart';
import '../services/sync_service.dart';
import '../services/van_sale_policy.dart';
import '../widgets/widgets.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({
    super.key,
    required this.sync,
    this.initialCustomer,
    this.onConsumedPrefill,
    this.onOpenMenu,
  });

  final SyncService sync;
  final String? initialCustomer;
  final VoidCallback? onConsumedPrefill;
  final VoidCallback? onOpenMenu;

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  List<Collection> _rows = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialCustomer != null) {
        _collect(prefillCustomer: widget.initialCustomer);
        widget.onConsumedPrefill?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CollectionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCustomer != null &&
        widget.initialCustomer != oldWidget.initialCustomer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _collect(prefillCustomer: widget.initialCustomer);
        widget.onConsumedPrefill?.call();
      });
    }
  }

  Future<void> _load() async {
    final rows = await vanSaleRepo.listCollections();
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _collect({String? prefillCustomer}) async {
    if (_saving) return;
    final session = VanSaleAuthScope.maybeOf(context)?.session;

    CustomerModel? selected;
    var customer = prefillCustomer?.trim() ?? '';
    if (customer.isNotEmpty) {
      final hits = await customerRepository.search(query: customer, limit: 8);
      for (final c in hits.items) {
        if (c.displayName == customer ||
            c.customerName == customer ||
            c.erpName == customer) {
          selected = c;
          customer = c.displayName;
          break;
        }
      }
    }

    final amount = TextEditingController();
    var method = 'Cash';

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Record collection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Customer',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  customer.isEmpty ? 'Search customers…' : customer,
                  style: TextStyle(
                    color: customer.isEmpty ? Theme.of(ctx).hintColor : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: session == null
                      ? null
                      : () async {
                          final picked =
                              await Navigator.of(context).push<CustomerModel>(
                            MaterialPageRoute(
                              builder: (_) => CustomerSearchPage(
                                session: session,
                                sync: widget.sync,
                                selectMode: true,
                                initialQuery: customer,
                              ),
                            ),
                          );
                          if (picked == null) return;
                          setLocal(() {
                            selected = picked;
                            customer = picked.displayName;
                          });
                        },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Search customer'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 10),
              DropdownMenu<String>(
                initialSelection: method,
                label: const Text('Method'),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: 'Cash', label: 'Cash'),
                  DropdownMenuEntry(value: 'Card', label: 'Card'),
                  DropdownMenuEntry(value: 'Transfer', label: 'Transfer'),
                ],
                onSelected: (v) => setLocal(() => method = v ?? 'Cash'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    if (customer.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a customer')),
      );
      amount.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      if (selected != null) {
        await customerRepository.markRecent(selected!.id);
      }
      String? salesInvoice;
      final orders = await vanSaleRepo.listOrders();
      for (final o in orders) {
        if (o.customerName == customer.trim() &&
            o.erpName != null &&
            o.erpName!.isNotEmpty &&
            o.syncStatus == SyncStatus.uploaded) {
          salesInvoice = o.erpName;
          break;
        }
      }
      await vanSaleRepo.recordCollection(
        customerName: customer.trim(),
        amount: double.tryParse(amount.text) ?? 0,
        method: method,
        salesInvoice: salesInvoice,
        session: widget.sync.session,
      );
      if (VanSalePolicy.instance.shouldAttemptFlushAfterWrite) {
        await widget.sync.flush(pullTrips: false);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      amount.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0, (s, c) => s + c.amount);
    final theme = Theme.of(context);

    return PageScaffold(
      title: 'Cash',
      subtitle: 'Payment Entry · safe client_id sync',
      onOpenMenu: widget.onOpenMenu,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _collect(),
        icon: const Icon(Icons.payments_outlined),
        label: Text(_saving ? 'Saving…' : 'Collect'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              child: ListTile(
                leading: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Collected today'),
                trailing: Text(
                  money(total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const EmptyHint(
                    'No collections yet',
                    icon: Icons.payments_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = _rows[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          title: Text(
                            c.customerName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${c.method} · ${timeLabel(c.collectedAt)}\n'
                            '${c.clientId}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(c.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SyncBadge(status: c.syncStatus),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

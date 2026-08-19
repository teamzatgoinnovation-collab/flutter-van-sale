import 'package:flutter/material.dart';

import '../customer/models/customer_model.dart';
import '../customer/pages/customer_search_page.dart';
import '../customer/repositories/customer_repository.dart';
import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../services/aging_service.dart';
import '../services/auth_scope.dart';
import '../services/sync_service.dart';
import '../services/van_sale_policy.dart';
import '../theme.dart';
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

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
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
    final referenceCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var method = 'Cash';
    List<Map<String, dynamic>> invoices = const [];
    String? selectedInvoice;
    var invoicesLoading = false;

    try {
      if (!mounted) return;

      Future<void> loadOutstanding(
        void Function(void Function()) setLocal,
      ) async {
        final sess = session ?? widget.sync.session;
        final target = selected?.erpName ?? customer;
        if (target.isEmpty || !sess.connected) return;
        setLocal(() => invoicesLoading = true);
        try {
          final detail = await AgingService(sess).detail(customer: target);
          setLocal(() {
            invoices = detail;
            invoicesLoading = false;
          });
        } catch (_) {
          setLocal(() {
            invoices = const [];
            invoicesLoading = false;
          });
        }
      }

      var startedInitialLoad = false;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            if (!startedInitialLoad && customer.isNotEmpty) {
              startedInitialLoad = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => loadOutstanding(setLocal),
              );
            }
            final scheme = Theme.of(ctx).colorScheme;
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.lg,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Record collection',
                      style: Theme.of(
                        ctx,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Customer',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      child: Text(
                        customer.isEmpty ? 'Search customers…' : customer,
                        style: TextStyle(
                          color: customer.isEmpty ? Theme.of(ctx).hintColor : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          final sess = session ?? widget.sync.session;
                          final picked =
                              await Navigator.of(
                                context,
                                rootNavigator: true,
                              ).push<CustomerModel>(
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => CustomerSearchPage(
                                    session: sess,
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
                            invoices = const [];
                            selectedInvoice = null;
                          });
                          await loadOutstanding(setLocal);
                        },
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Search customer'),
                      ),
                    ),
                    if (customer.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Outstanding invoices',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (invoicesLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (invoices.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text(
                            'No open invoices for this customer',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        )
                      else
                        ...invoices.map((inv) {
                          final name = '${inv['name'] ?? ''}';
                          final due =
                              '${inv['due_date'] ?? inv['posting_date'] ?? ''}';
                          final outstandingAmt =
                              (inv['outstanding'] as num?)?.toDouble() ??
                              (inv['outstanding_amount'] as num?)
                                  ?.toDouble() ??
                              0;
                          final isSelected = selectedInvoice == name;
                          return Card(
                            margin: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            color: isSelected
                                ? scheme.primaryContainer.withValues(
                                    alpha: 0.35,
                                  )
                                : null,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: isSelected ? scheme.primary : null,
                              ),
                              title: Text(name),
                              subtitle: Text('Due $due'),
                              trailing: Text(
                                money(outstandingAmt),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onTap: () => setLocal(() {
                                selectedInvoice = isSelected ? null : name;
                                if (!isSelected) {
                                  amount.text = money(outstandingAmt);
                                }
                              }),
                            ),
                          );
                        }),
                      if (selectedInvoice != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                setLocal(() => selectedInvoice = null),
                            child: const Text('Collect without an invoice'),
                          ),
                        ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setLocal(() {}),
                      style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount to collect',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Payment method',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        for (final m in VanSaleRepo.kCollectionMethods)
                          ChoiceChip(
                            label: Text(m),
                            selected: method == m,
                            onSelected: (_) => setLocal(() => method = m),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: referenceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reference / cheque no. (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                'Collect${amount.text.trim().isEmpty ? '' : ' · ${money(double.tryParse(amount.text.trim()) ?? 0)}'}',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      if (ok != true || !mounted) return;
      if (customer.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pick a customer')));
        return;
      }
      final parsed = double.tryParse(amount.text.trim());
      if (parsed == null || parsed <= 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
        return;
      }

      setState(() => _saving = true);
      try {
        if (selected != null) {
          await customerRepository.markRecent(selected!.id);
        }
        await vanSaleRepo.recordCollection(
          customerName: customer.trim(),
          amount: parsed,
          method: method,
          salesInvoice: selectedInvoice,
          reference: referenceCtrl.text.trim(),
          notes: notesCtrl.text.trim(),
          session: widget.sync.session,
          customerErpName: selected?.erpName,
        );
        if (VanSalePolicy.instance.shouldAttemptFlushAfterWrite) {
          try {
            await widget.sync.flush(pullTrips: false);
          } catch (_) {}
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    } finally {
      amount.dispose();
      referenceCtrl.dispose();
      notesCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayTotal = _rows
        .where((c) => _isToday(c.collectedAt))
        .fold<double>(0, (s, c) => s + c.amount);

    return PageScaffold(
      title: 'Cash',
      subtitle: 'Record collections · sync when online',
      onOpenMenu: widget.onOpenMenu,
      floatingActionButton: HeroMode(
        enabled: false,
        child: FloatingActionButton.extended(
          heroTag: 'van_sale_cash_fab',
          onPressed: _saving ? null : () => _collect(),
          icon: const Icon(Icons.payments_outlined),
          label: Text(_saving ? 'Saving…' : 'Collect'),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: KpiCard(
              title: 'Collected today',
              value: money(todayTotal),
              icon: Icons.account_balance_wallet_outlined,
              accentColor: kStatusSuccess,
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const AppEmptyState(
                    'No collections yet',
                    icon: Icons.payments_outlined,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      88,
                    ),
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final c = _rows[i];
                      return _CollectionTile(collection: c);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.collection});

  final Collection collection;

  static const _methodIcons = {
    'Cash': Icons.payments_outlined,
    'Credit Card': Icons.credit_card_outlined,
    'Wire Transfer': Icons.account_balance_outlined,
    'Cheque': Icons.receipt_long_outlined,
    'Other': Icons.more_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kStatusSuccess.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                _methodIcons[collection.method] ?? Icons.payments_outlined,
                color: kStatusSuccess,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.customerName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${collection.method} · ${timeLabel(collection.collectedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if ((collection.salesInvoice ?? '').isNotEmpty ||
                      (collection.reference ?? '').isNotEmpty)
                    Text(
                      [
                        if ((collection.salesInvoice ?? '').isNotEmpty)
                          collection.salesInvoice!,
                        if ((collection.reference ?? '').isNotEmpty)
                          'Ref ${collection.reference}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(collection.amount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                SyncBadge(status: collection.syncStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

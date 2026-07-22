import 'package:flutter/material.dart';

import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../services/sync_service.dart';
import '../widgets/widgets.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({
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
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _query = TextEditingController();
  List<VanOrder> _orders = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialCustomer != null) {
        _newOrder(prefillCustomer: widget.initialCustomer);
        widget.onConsumedPrefill?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant OrdersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCustomer != null &&
        widget.initialCustomer != oldWidget.initialCustomer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _newOrder(prefillCustomer: widget.initialCustomer);
        widget.onConsumedPrefill?.call();
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final orders = await vanSaleRepo.listOrders(query: _query.text);
    if (!mounted) return;
    setState(() => _orders = orders);
  }

  Future<void> _newOrder({String? prefillCustomer}) async {
    if (_saving) return;
    final stock = await vanSaleRepo.listStock();
    final stops = await vanSaleRepo.listStops();
    if (!mounted) return;
    if (stock.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No van stock to sell')),
      );
      return;
    }

    final customers = [
      if (prefillCustomer != null && prefillCustomer.trim().isNotEmpty)
        prefillCustomer.trim(),
      ...stops.map((s) => s.customerName),
    ];
    final uniqueCustomers = <String>{...customers}.toList();
    var customer = uniqueCustomers.isNotEmpty
        ? uniqueCustomers.first
        : (prefillCustomer ?? 'Customer');
    final qtys = <String, double>{
      for (final s in stock) s.itemCode: 0,
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          double total = 0;
          for (final s in stock) {
            total += (qtys[s.itemCode] ?? 0) * s.unitPrice;
          }
          return AlertDialog(
            title: const Text('Sell from van'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownMenu<String>(
                      initialSelection: customer,
                      label: const Text('Customer'),
                      expandedInsets: EdgeInsets.zero,
                      dropdownMenuEntries: [
                        for (final c in uniqueCustomers)
                          DropdownMenuEntry(value: c, label: c),
                      ],
                      onSelected: (v) =>
                          setLocal(() => customer = v ?? customer),
                    ),
                    const SizedBox(height: 12),
                    ...stock.map((s) {
                      final q = qtys[s.itemCode] ?? 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.itemName),
                        subtitle: Text(
                          '${money(s.qty)} ${s.uom} · ${money(s.unitPrice)} each',
                        ),
                        trailing: SizedBox(
                          width: 72,
                          child: TextFormField(
                            initialValue: q == 0 ? '' : money(q),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Qty',
                              isDense: true,
                            ),
                            onChanged: (v) => setLocal(() {
                              qtys[s.itemCode] = double.tryParse(v) ?? 0;
                            }),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total ${money(total)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Queue sale'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || !mounted) return;

    final lines = <OrderLine>[];
    for (final s in stock) {
      final q = qtys[s.itemCode] ?? 0;
      if (q <= 0) continue;
      lines.add(
        OrderLine(
          itemCode: s.itemCode,
          itemName: s.itemName,
          qty: q,
          unitPrice: s.unitPrice,
        ),
      );
    }
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one qty')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await vanSaleRepo.createOrder(
        customerName: customer.trim().isEmpty ? 'Customer' : customer.trim(),
        lines: lines,
      );
      await widget.sync.flush(pullTrips: false);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale saved on device · sync queued'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Sell',
      subtitle: 'Sales Invoice · client_id sync',
      onOpenMenu: widget.onOpenMenu,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _newOrder(),
        icon: const Icon(Icons.add),
        label: Text(_saving ? 'Saving…' : 'Sell'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                hintText: 'Filter orders…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _orders.isEmpty
                ? const EmptyHint(
                    'No sales yet',
                    icon: Icons.point_of_sale_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    itemCount: _orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final o = _orders[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          title: Text(
                            o.customerName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${o.itemsLabel}\n${o.clientId}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(o.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SyncBadge(status: o.syncStatus),
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

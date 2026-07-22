import 'package:flutter/material.dart';

import '../customer/models/customer_model.dart';
import '../customer/pages/customer_form_page.dart';
import '../customer/pages/customer_search_page.dart';
import '../customer/repositories/customer_repository.dart';
import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../product/models/product_model.dart';
import '../product/pages/product_form_page.dart';
import '../product/pages/product_search_page.dart';
import '../product/repositories/product_repository.dart';
import '../services/auth_scope.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import '../services/van_sale_policy.dart';
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

  VanSaleSession? get _session => VanSaleAuthScope.maybeOf(context)?.session;

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

  Future<CustomerModel?> _pickCustomer({String? initialQuery}) async {
    final session = _session;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session unavailable')),
      );
      return null;
    }
    return Navigator.of(context).push<CustomerModel>(
      MaterialPageRoute(
        builder: (_) => CustomerSearchPage(
          session: session,
          sync: widget.sync,
          selectMode: true,
          initialQuery: initialQuery,
        ),
      ),
    );
  }

  Future<String?> _createCustomerDialog() async {
    final session = _session;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session unavailable')),
      );
      return null;
    }
    // Offline-first form — works without connectivity.
    final created = await Navigator.of(context).push<CustomerModel>(
      MaterialPageRoute(
        builder: (_) =>
            CustomerFormPage(session: session, sync: widget.sync),
      ),
    );
    if (created == null) return null;
    return created.displayName;
  }

  Future<StockLine?> _pickProduct() async {
    final session = _session;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session unavailable')),
      );
      return null;
    }
    final picked = await Navigator.of(context).push<ProductModel>(
      MaterialPageRoute(
        builder: (_) => ProductSearchPage(
          session: session,
          sync: widget.sync,
          selectMode: true,
        ),
      ),
    );
    if (picked == null) return null;
    await productRepository.markRecent(picked.id);
    final existing = await vanSaleRepo.getStock(picked.displayCode) ??
        await vanSaleRepo.getStock(picked.itemCode);
    return existing ??
        StockLine(
          itemCode: picked.displayCode,
          itemName: picked.itemName,
          qty: picked.stockQty,
          uom: picked.stockUom,
          unitPrice: picked.displayPrice,
        );
  }

  Future<StockLine?> _createProductDialog() async {
    final session = _session;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session unavailable')),
      );
      return null;
    }
    final created = await Navigator.of(context).push<ProductModel>(
      MaterialPageRoute(
        builder: (_) =>
            ProductFormPage(session: session, sync: widget.sync),
      ),
    );
    if (created == null) return null;
    final line = await vanSaleRepo.getStock(created.displayCode) ??
        await vanSaleRepo.getStock(created.itemCode);
    return line ??
        StockLine(
          itemCode: created.displayCode,
          itemName: created.itemName,
          qty: created.openingQuantity,
          uom: created.stockUom,
          unitPrice: created.sellingRate,
        );
  }

  Future<void> _newOrder({String? prefillCustomer}) async {
    if (_saving) return;
    var stock = await vanSaleRepo.listStock();
    if (!mounted) return;

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
    final qtys = <String, double>{for (final s in stock) s.itemCode: 0};

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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Customer',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        customer.isEmpty ? 'Search customers…' : customer,
                        style: TextStyle(
                          color: customer.isEmpty
                              ? Theme.of(ctx).hintColor
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final picked = await _pickCustomer(
                              initialQuery: customer,
                            );
                            if (picked == null) return;
                            setLocal(() {
                              selected = picked;
                              customer = picked.displayName;
                            });
                          },
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('Search'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final created = await _createCustomerDialog();
                            if (created == null) return;
                            setLocal(() {
                              customer = created;
                              selected = null;
                            });
                          },
                          icon: const Icon(Icons.person_add_outlined, size: 18),
                          label: const Text('New'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final line = await _pickProduct();
                            if (line == null) return;
                            setLocal(() {
                              stock = [
                                ...stock.where(
                                  (s) => s.itemCode != line.itemCode,
                                ),
                                line,
                              ];
                              qtys[line.itemCode] =
                                  (qtys[line.itemCode] ?? 0) > 0
                                      ? qtys[line.itemCode]!
                                      : 1;
                            });
                          },
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('Search product'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final line = await _createProductDialog();
                            if (line == null) return;
                            setLocal(() {
                              stock = [
                                ...stock.where(
                                  (s) => s.itemCode != line.itemCode,
                                ),
                                line,
                              ];
                              qtys[line.itemCode] = qtys[line.itemCode] ?? 0;
                            });
                          },
                          icon: const Icon(Icons.add_box_outlined, size: 18),
                          label: const Text('New'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (stock.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No van stock yet. Search products, create one, '
                          'or Sync after setting warehouse.',
                        ),
                      )
                    else
                      ...stock.map((s) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.itemName),
                          subtitle: Text(
                            '${money(s.qty)} ${s.uom} · ${money(s.unitPrice)} each',
                          ),
                          trailing: SizedBox(
                            width: 72,
                            child: TextFormField(
                              initialValue: (qtys[s.itemCode] ?? 0) == 0
                                  ? ''
                                  : money(qtys[s.itemCode]!),
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
    if (customer.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick or create a customer')),
      );
      return;
    }
    if (lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pick at least one qty')));
      return;
    }

    setState(() => _saving = true);
    try {
      if (selected != null) {
        await customerRepository.markRecent(selected!.id);
      }
      await vanSaleRepo.createOrder(
        customerName: customer.trim(),
        lines: lines,
        session: widget.sync.session,
      );
      if (VanSalePolicy.instance.shouldAttemptFlushAfterWrite) {
        await widget.sync.flush(pullTrips: false);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              VanSalePolicy.instance.shouldAttemptFlushAfterWrite
                  ? 'Sale saved · sync queued'
                  : 'Sale saved locally',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Sell',
      subtitle: 'Sales Invoice · create customer / product',
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
                          subtitle: Text('${o.itemsLabel}\n${o.clientId}'),
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

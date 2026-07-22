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
import '../services/session.dart';
import '../services/sync_service.dart';
import '../services/van_sale_policy.dart';
import '../widgets/widgets.dart';

/// Fullscreen sell cart — customer first, then add lines with large +/- steppers.
class SellOrderPage extends StatefulWidget {
  const SellOrderPage({
    super.key,
    required this.session,
    required this.sync,
    this.initialCustomer,
  });

  final VanSaleSession session;
  final SyncService sync;
  final String? initialCustomer;

  @override
  State<SellOrderPage> createState() => _SellOrderPageState();
}

class _CartLine {
  _CartLine({required this.stock, required this.qty});

  StockLine stock;
  double qty;

  double get amount => qty * stock.unitPrice;

  bool get overStock {
    if (VanSalePolicy.instance.allowNegativeStock) return false;
    return qty > stock.qty;
  }
}

class _SellOrderPageState extends State<SellOrderPage> {
  final _stockFilter = TextEditingController();
  CustomerModel? _customer;
  String _customerLabel = '';
  final _cart = <String, _CartLine>{};
  List<StockLine> _vanStock = const [];
  bool _loading = true;
  bool _saving = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _stockFilter.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final stock = await vanSaleRepo.listStock();
      CustomerModel? selected;
      var label = widget.initialCustomer?.trim() ?? '';
      if (label.isNotEmpty) {
        final hits = await customerRepository.search(query: label, limit: 8);
        for (final c in hits.items) {
          if (c.displayName == label ||
              c.customerName == label ||
              c.erpName == label) {
            selected = c;
            label = c.displayName;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _vanStock = stock;
        _customer = selected;
        _customerLabel = label;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _banner = 'Could not load van stock: $e';
      });
    }
  }

  double get _total =>
      _cart.values.fold<double>(0, (s, line) => s + line.amount);

  int get _lineCount => _cart.values.where((l) => l.qty > 0).length;

  bool get _hasOverStock => _cart.values.any((l) => l.overStock);

  List<StockLine> get _filteredStock {
    final q = _stockFilter.text.trim().toLowerCase();
    final list = _vanStock.where((s) {
      if (q.isEmpty) return true;
      return s.itemName.toLowerCase().contains(q) ||
          s.itemCode.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      final inCartA = (_cart[a.itemCode]?.qty ?? 0) > 0 ? 0 : 1;
      final inCartB = (_cart[b.itemCode]?.qty ?? 0) > 0 ? 0 : 1;
      if (inCartA != inCartB) return inCartA.compareTo(inCartB);
      return a.itemName.compareTo(b.itemName);
    });
    return list;
  }

  void _setQty(StockLine stock, double qty) {
    setState(() {
      _banner = null;
      var next = qty < 0 ? 0.0 : qty;
      if (!VanSalePolicy.instance.allowNegativeStock && next > stock.qty) {
        next = stock.qty;
        _banner =
            'Only ${money(stock.qty)} ${stock.uom} left for ${stock.itemName}';
      }
      if (next <= 0) {
        _cart.remove(stock.itemCode);
      } else {
        _cart[stock.itemCode] = _CartLine(stock: stock, qty: next);
      }
    });
  }

  void _bump(StockLine stock, double delta) {
    final current = _cart[stock.itemCode]?.qty ?? 0;
    _setQty(stock, current + delta);
  }

  Future<void> _pickCustomer() async {
    final picked = await Navigator.of(context).push<CustomerModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CustomerSearchPage(
          session: widget.session,
          sync: widget.sync,
          selectMode: true,
          initialQuery: _customerLabel,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customer = picked;
      _customerLabel = picked.displayName;
      _banner = null;
    });
  }

  Future<void> _createCustomer() async {
    final created = await Navigator.of(context).push<CustomerModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            CustomerFormPage(session: widget.session, sync: widget.sync),
      ),
    );
    if (created == null || !mounted) return;
    setState(() {
      _customer = created;
      _customerLabel = created.displayName;
      _banner = null;
    });
  }

  Future<void> _addFromSearch() async {
    final picked = await Navigator.of(context).push<ProductModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductSearchPage(
          session: widget.session,
          sync: widget.sync,
          selectMode: true,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await productRepository.markRecent(picked.id);
    final existing = await vanSaleRepo.getStock(picked.displayCode) ??
        await vanSaleRepo.getStock(picked.itemCode);
    final line = existing ??
        StockLine(
          itemCode: picked.displayCode,
          itemName: picked.itemName,
          qty: picked.stockQty,
          uom: picked.stockUom,
          unitPrice: picked.displayPrice,
        );
    if (existing == null) {
      await vanSaleRepo.db.upsertStockLine(line);
    }
    if (!mounted) return;
    setState(() {
      final known = [
        ..._vanStock.where((s) => s.itemCode != line.itemCode),
        line,
      ];
      _vanStock = known;
    });
    final current = _cart[line.itemCode]?.qty ?? 0;
    _setQty(line, current > 0 ? current : 1);
  }

  Future<void> _createProduct() async {
    final created = await Navigator.of(context).push<ProductModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            ProductFormPage(session: widget.session, sync: widget.sync),
      ),
    );
    if (created == null || !mounted) return;
    var line = await vanSaleRepo.getStock(created.displayCode) ??
        await vanSaleRepo.getStock(created.itemCode);
    if (line == null) {
      line = StockLine(
        itemCode: created.displayCode,
        itemName: created.itemName,
        qty: created.openingQuantity,
        uom: created.stockUom,
        unitPrice: created.sellingRate,
      );
      await vanSaleRepo.db.upsertStockLine(line);
    }
    if (!mounted) return;
    setState(() {
      _vanStock = [
        ..._vanStock.where((s) => s.itemCode != line!.itemCode),
        line!,
      ];
    });
    _setQty(line, 1);
  }

  Future<void> _queueSale() async {
    if (_saving) return;
    final customer = _customerLabel.trim();
    if (customer.isEmpty) {
      setState(() => _banner = 'Pick or create a customer first');
      return;
    }
    final lines = _cart.values
        .where((l) => l.qty > 0)
        .map(
          (l) => OrderLine(
            itemCode: l.stock.itemCode,
            itemName: l.stock.itemName,
            qty: l.qty,
            unitPrice: l.stock.unitPrice,
          ),
        )
        .toList();
    if (lines.isEmpty) {
      setState(() => _banner = 'Add at least one product qty');
      return;
    }
    if (_hasOverStock) {
      setState(
        () => _banner =
            'Some lines exceed van stock. Lower qty or enable negative stock in Settings.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _banner = null;
    });
    try {
      if (_customer != null) {
        await customerRepository.markRecent(_customer!.id);
      }
      await vanSaleRepo.createOrder(
        customerName: customer,
        lines: lines,
        session: widget.sync.session,
      );
      // Local sale succeeded — never re-queue on flush failure.
      if (VanSalePolicy.instance.shouldAttemptFlushAfterWrite) {
        try {
          await widget.sync.flush(pullTrips: false);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _banner = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          IconButton(
            tooltip: 'Search product',
            onPressed: _loading || _saving ? null : _addFromSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'New product',
            onPressed: _loading || _saving ? null : _createProduct,
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_banner != null)
                  Material(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: scheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _banner!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _banner = null),
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: scheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _CustomerCard(
                        label: _customerLabel,
                        customer: _customer,
                        enabled: !_saving,
                        onTap: _pickCustomer,
                        onNew: _createCustomer,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Cart',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lineCount == 0
                            ? 'Tap + on van stock below, or search a product'
                            : '$_lineCount item${_lineCount == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_cart.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 22,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.shopping_basket_outlined,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Cart is empty',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._cart.values.map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CartLineTile(
                              line: line,
                              enabled: !_saving,
                              onMinus: () => _bump(line.stock, -1),
                              onPlus: () => _bump(line.stock, 1),
                              onQtyChanged: (v) => _setQty(line.stock, v),
                              onRemove: () => _setQty(line.stock, 0),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Van stock',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _stockFilter,
                        enabled: !_saving,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Filter van stock…',
                          prefixIcon: Icon(Icons.filter_list),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_vanStock.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No van stock yet. Search or create a product, '
                              'or sync after setting warehouse.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._filteredStock.map((s) {
                          final qty = _cart[s.itemCode]?.qty ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _StockQuickTile(
                              stock: s,
                              cartQty: qty,
                              enabled: !_saving,
                              onAdd: () => _bump(s, 1),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                _SellBottomBar(
                  total: _total,
                  lineCount: _lineCount,
                  saving: _saving,
                  canSubmit: !_saving &&
                      _customerLabel.trim().isNotEmpty &&
                      _lineCount > 0 &&
                      !_hasOverStock,
                  onSubmit: _queueSale,
                ),
              ],
            ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.label,
    required this.customer,
    required this.enabled,
    required this.onTap,
    required this.onNew,
  });

  final String label;
  final CustomerModel? customer;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = label.trim().isEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  empty ? Icons.person_search_outlined : Icons.person_rounded,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      empty ? 'Tap to search…' : label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: empty ? scheme.onSurfaceVariant : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customer != null &&
                        customer!.mobileNo.trim().isNotEmpty)
                      Text(
                        customer!.mobileNo,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'New customer',
                onPressed: enabled ? onNew : null,
                icon: const Icon(Icons.person_add_outlined),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
    required this.onQtyChanged,
    required this.onRemove,
  });

  final _CartLine line;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onQtyChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final over = line.overStock;

    return Card(
      color: over ? scheme.errorContainer.withValues(alpha: 0.35) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.stock.itemName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${money(line.stock.qty)} ${line.stock.uom} on van · '
                        '${money(line.stock.unitPrice)} each',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: over
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _QtyStepper(
                  qty: line.qty,
                  enabled: enabled,
                  warn: over,
                  onMinus: onMinus,
                  onPlus: onPlus,
                  onQtyChanged: onQtyChanged,
                ),
                const Spacer(),
                Text(
                  money(line.amount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (over) ...[
              const SizedBox(height: 6),
              Text(
                'Exceeds van stock',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StockQuickTile extends StatelessWidget {
  const _StockQuickTile({
    required this.stock,
    required this.cartQty,
    required this.enabled,
    required this.onAdd,
  });

  final StockLine stock;
  final double cartQty;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final low = stock.qty <= VanSalePolicy.instance.lowStockThreshold;
    final inCart = cartQty > 0;

    return Card(
      color: inCart ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Text(
          stock.itemName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${money(stock.qty)} ${stock.uom}'
          '${low ? ' · low' : ''} · ${money(stock.unitPrice)}',
        ),
        trailing: FilledButton.tonal(
          onPressed: enabled &&
                  (VanSalePolicy.instance.allowNegativeStock || stock.qty > 0)
              ? onAdd
              : null,
          child: Text(inCart ? '+1' : 'Add'),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatefulWidget {
  const _QtyStepper({
    required this.qty,
    required this.enabled,
    required this.warn,
    required this.onMinus,
    required this.onPlus,
    required this.onQtyChanged,
  });

  final double qty;
  final bool enabled;
  final bool warn;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onQtyChanged;

  @override
  State<_QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<_QtyStepper> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: money(widget.qty));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _QtyStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.qty != widget.qty) {
      final next = money(widget.qty);
      if (_controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = widget.warn ? scheme.error : scheme.outlineVariant;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        color: Theme.of(context).cardColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: widget.enabled ? widget.onMinus : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 52,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v.trim());
                if (v.trim().isEmpty) {
                  widget.onQtyChanged(0);
                } else if (parsed != null) {
                  widget.onQtyChanged(parsed);
                }
              },
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: widget.enabled ? widget.onPlus : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _SellBottomBar extends StatelessWidget {
  const _SellBottomBar({
    required this.total,
    required this.lineCount,
    required this.saving,
    required this.canSubmit,
    required this.onSubmit,
  });

  final double total;
  final int lineCount;
  final bool saving;
  final bool canSubmit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      lineCount == 0
                          ? 'No items'
                          : '$lineCount item${lineCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      money(total),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: canSubmit ? onSubmit : null,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(saving ? 'Saving…' : 'Queue sale'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

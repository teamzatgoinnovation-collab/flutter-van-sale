import 'package:flutter/material.dart';

import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../services/prefs.dart';
import '../services/sync_service.dart';
import '../services/van_sale_policy.dart';
import '../widgets/widgets.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key, required this.sync, this.onOpenMenu});

  final SyncService sync;
  final VoidCallback? onOpenMenu;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  List<StockLine> _stock = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stock = await vanSaleRepo.listStock();
    if (!mounted) return;
    setState(() => _stock = stock);
  }

  Future<void> _adjust(StockLine line, {required bool load}) async {
    if (_saving) return;
    final qty = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          load
              ? 'Adjust in · ${line.itemName}'
              : 'Adjust out · ${line.itemName}',
        ),
        content: TextField(
          controller: qty,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: load
                ? 'Qty to receive (damage/found)'
                : 'Qty to issue (damage/write-off)',
            helperText: 'Prefer Transfer for warehouse↔van moves',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = double.tryParse(qty.text) ?? 0;
    qty.dispose();
    if (n <= 0) return;

    setState(() => _saving = true);
    try {
      await vanSaleRepo.adjustStock(
        itemCode: line.itemCode,
        delta: load ? n : -n,
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _transfer(StockLine line, {required bool intoVan}) async {
    if (_saving) return;
    final prefs = VanSalePrefs.instance;
    final vanWh = prefs.warehouse.trim();
    final sourceWh = prefs.sourceWarehouse.trim();
    if (vanWh.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set van warehouse in Settings first')),
      );
      return;
    }
    if (sourceWh.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set source / depot warehouse in Settings first'),
        ),
      );
      return;
    }

    final qty = TextEditingController(text: '1');
    final from = intoVan ? sourceWh : vanWh;
    final to = intoVan ? vanWh : sourceWh;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          intoVan
              ? 'Transfer in · ${line.itemName}'
              : 'Transfer out · ${line.itemName}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$from → $to'),
            const SizedBox(height: 12),
            TextField(
              controller: qty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Qty'),
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
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = double.tryParse(qty.text) ?? 0;
    qty.dispose();
    if (n <= 0) return;

    setState(() => _saving = true);
    try {
      await vanSaleRepo.transferStock(
        itemCode: line.itemCode,
        qty: n,
        fromWarehouse: from,
        toWarehouse: to,
        session: widget.sync.session,
      );
      if (VanSalePolicy.instance.shouldAttemptFlushAfterWrite) {
        await widget.sync.flush(pullTrips: false);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Queued transfer $n ${line.uom}')),
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
    final prefs = VanSalePrefs.instance;
    final source = prefs.sourceWarehouse.trim();
    final van = prefs.warehouse.trim();
    return PageScaffold(
      title: 'Van stock',
      subtitle: van.isEmpty
          ? 'Set van warehouse in Settings'
          : source.isEmpty
          ? 'Van $van · set source WH for transfers'
          : 'Transfer $source ↔ $van',
      onOpenMenu: widget.onOpenMenu,
      child: _stock.isEmpty
          ? const EmptyHint(
              'No stock for this warehouse. Set Van warehouse in Settings and Sync.',
              icon: Icons.inventory_2_outlined,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _stock.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final line = _stock[i];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    title: Text(
                      line.itemName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${line.itemCode} · ${money(line.unitPrice)} / ${line.uom}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${money(line.qty)} ${line.uom}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          tooltip: 'Transfer in',
                          onPressed: _saving
                              ? null
                              : () => _transfer(line, intoVan: true),
                          icon: const Icon(Icons.move_to_inbox_outlined),
                        ),
                        IconButton(
                          tooltip: 'Transfer out',
                          onPressed: _saving
                              ? null
                              : () => _transfer(line, intoVan: false),
                          icon: const Icon(Icons.outbox_outlined),
                        ),
                        PopupMenuButton<String>(
                          enabled: !_saving,
                          onSelected: (v) {
                            if (v == 'in') {
                              _adjust(line, load: true);
                            } else if (v == 'out') {
                              _adjust(line, load: false);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'in',
                              child: Text('Adjust in (damage/found)'),
                            ),
                            PopupMenuItem(
                              value: 'out',
                              child: Text('Adjust out (write-off)'),
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
  }
}

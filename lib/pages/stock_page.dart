import 'package:flutter/material.dart';

import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../services/sync_service.dart';
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
        title: Text(load ? 'Load ${line.itemName}' : 'Issue ${line.itemName}'),
        content: TextField(
          controller: qty,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: load ? 'Qty to load onto van' : 'Qty to issue / return',
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
      );
      await widget.sync.flush(pullTrips: false);
      await _load();
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
      title: 'Van stock',
      subtitle: 'ERPNext Bin · set warehouse in Settings',
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
                      horizontal: 12,
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
                          tooltip: 'Load',
                          onPressed: _saving
                              ? null
                              : () => _adjust(line, load: true),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Issue',
                          onPressed: _saving
                              ? null
                              : () => _adjust(line, load: false),
                          icon: const Icon(Icons.remove_circle_outline),
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

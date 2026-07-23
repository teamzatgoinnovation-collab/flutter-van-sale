import 'package:flutter/material.dart';

import '../services/auth_scope.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import '../services/van_sale_invoice_service.dart';
import '../services/van_sale_policy.dart';
import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import 'sell_order_page.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({
    super.key,
    required this.sync,
    this.initialCustomer,
    this.initialTripId,
    this.onConsumedPrefill,
    this.onOpenMenu,
  });

  final SyncService sync;
  final String? initialCustomer;
  final String? initialTripId;
  final VoidCallback? onConsumedPrefill;
  final VoidCallback? onOpenMenu;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _query = TextEditingController();
  List<VanOrder> _orders = const [];
  bool _saving = false;

  VanSaleSession get _session =>
      VanSaleAuthScope.maybeOf(context)?.session ?? widget.sync.session;

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_onSyncChanged);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialCustomer != null || widget.initialTripId != null) {
        _newOrder(
          prefillCustomer: widget.initialCustomer,
          tripId: widget.initialTripId,
        );
        widget.onConsumedPrefill?.call();
      }
    });
  }

  void _onSyncChanged() {
    if (!mounted || widget.sync.isRunning) return;
    _load();
  }

  @override
  void dispose() {
    widget.sync.removeListener(_onSyncChanged);
    _query.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OrdersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sync != widget.sync) {
      oldWidget.sync.removeListener(_onSyncChanged);
      widget.sync.addListener(_onSyncChanged);
    }
    if ((widget.initialCustomer != null &&
            widget.initialCustomer != oldWidget.initialCustomer) ||
        (widget.initialTripId != null &&
            widget.initialTripId != oldWidget.initialTripId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _newOrder(
          prefillCustomer: widget.initialCustomer,
          tripId: widget.initialTripId,
        );
        widget.onConsumedPrefill?.call();
      });
    }
  }

  Future<void> _load() async {
    final orders = await vanSaleRepo.listOrders(query: _query.text);
    if (!mounted) return;
    setState(() => _orders = orders);
  }

  Future<void> _newOrder({String? prefillCustomer, String? tripId}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final created = await Navigator.of(context, rootNavigator: true)
          .push<Object?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SellOrderPage(
            session: _session,
            sync: widget.sync,
            initialCustomer: prefillCustomer,
            tripId: tripId,
          ),
        ),
      );
      if (created != null && mounted) {
        await _load();
        if (!mounted) return;
        final order = created is VanOrder
            ? created
            : (_orders.isEmpty ? null : _orders.first);
        final erpName = order?.erpName;
        final messenger = ScaffoldMessenger.of(context);
        if (erpName != null &&
            erpName.isNotEmpty &&
            order?.syncStatus == SyncStatus.uploaded) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Invoiced · $erpName'),
              action: SnackBarAction(
                label: 'Invoice',
                onPressed: () {
                  VanSaleInvoiceService.showActions(
                    context,
                    session: _session,
                    erpName: erpName,
                  );
                },
              ),
            ),
          );
        } else {
          final pending = order?.syncStatus == SyncStatus.failed ||
              order?.syncStatus == SyncStatus.pending ||
              order?.syncStatus == SyncStatus.retry;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                pending &&
                        VanSalePolicy.instance.shouldAttemptFlushAfterWrite
                    ? 'Sale saved · invoice pending sync — open Sync to retry'
                    : VanSalePolicy.instance.shouldAttemptFlushAfterWrite
                        ? 'Sale saved · sync queued'
                        : 'Sale saved locally',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openInvoice(VanOrder order) async {
    final erp = order.erpName;
    if (erp == null || erp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice syncs after upload')),
      );
      return;
    }
    await VanSaleInvoiceService.showActions(
      context,
      session: _session,
      erpName: erp,
    );
  }

  String _whenLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final t = timeLabel(dt);
    if (day == today) return 'Today · $t';
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return 'Yesterday · $t';
    return '${dt.day}/${dt.month} · $t';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PageScaffold(
      title: 'Sell',
      subtitle: 'Queue sales · sync when online',
      onOpenMenu: widget.onOpenMenu,
      floatingActionButton: HeroMode(
        enabled: false,
        child: FloatingActionButton.extended(
          heroTag: 'van_sale_sell_fab',
          onPressed: _saving ? null : () => _newOrder(),
          icon: Icon(_saving ? Icons.hourglass_top : Icons.point_of_sale),
          label: Text(_saving ? 'Opening…' : 'New sale'),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                hintText: 'Filter by customer…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _orders.isEmpty
                ? EmptyHint(
                    'No sales yet — tap New sale',
                    icon: Icons.point_of_sale_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    itemCount: _orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final o = _orders[i];
                      final canPrint =
                          (o.erpName ?? '').isNotEmpty &&
                          o.syncStatus == SyncStatus.uploaded;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onLongPress: canPrint ? () => _openInvoice(o) : null,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o.customerName,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        o.itemsLabel,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _whenLabel(o.createdAt),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      if ((o.erpName ?? '').isNotEmpty)
                                        Text(
                                          o.erpName!,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      money(o.amount),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    SyncBadge(status: o.syncStatus),
                                    if (canPrint)
                                      IconButton(
                                        tooltip: 'Tax invoice',
                                        onPressed: () => _openInvoice(o),
                                        icon: const Icon(
                                          Icons.picture_as_pdf_outlined,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
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

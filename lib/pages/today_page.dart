import 'package:flutter/material.dart';

import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../services/sync_service.dart';
import '../widgets/widgets.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    required this.sync,
    required this.onSell,
    required this.onCollect,
    this.onOpenMenu,
  });

  final SyncService sync;
  final void Function(String customer) onSell;
  final void Function(String customer) onCollect;
  final VoidCallback? onOpenMenu;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _busy = false;
  DaySummary? _summary;
  List<RouteStop> _stops = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary = await vanSaleRepo.summary();
    final stops = await vanSaleRepo.listStops();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _stops = stops;
    });
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final result = await widget.sync.flush();
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    final pending = await vanSaleRepo.syncCounts();
    if (!mounted) return;
    final left =
        (pending['queued'] ?? 0) +
        (pending['awaiting_erp'] ?? 0) +
        (pending['failed'] ?? 0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.uploaded == 0 &&
                  result.failed == 0 &&
                  result.conflicts == 0 &&
                  left == 0
              ? 'Nothing to sync'
              : 'Uploaded ${result.uploaded} · conflicts ${result.conflicts} · '
                    'failed ${result.failed} · still open $left',
        ),
      ),
    );
  }

  Future<void> _setVisit(RouteStop stop, VisitStatus status) async {
    await vanSaleRepo.updateVisit(stop.id, status);
    await widget.sync.flush(pullTrips: false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final theme = Theme.of(context);

    return PageScaffold(
      title: 'VanSale',
      subtitle: vanSaleRepo.routeName,
      onOpenMenu: widget.onOpenMenu,
      actions: [
        IconButton(
          tooltip: 'Sync outbox',
          onPressed: _busy ? null : _sync,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_sync_outlined),
        ),
      ],
      child: summary == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text(
                  'Today on the route',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sell from the van, collect cash, and complete visits. '
                  'Changes sync when you are online.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                  children: [
                    StatTile(
                      label: 'Stops done',
                      value: '${summary.stopsDone}/${summary.stopsTotal}',
                      icon: Icons.route_outlined,
                    ),
                    StatTile(
                      label: 'Orders open',
                      value: '${summary.ordersQueued}',
                      icon: Icons.outbox_outlined,
                    ),
                    StatTile(
                      label: 'Collections',
                      value: money(summary.collectionsToday),
                      icon: Icons.payments_outlined,
                    ),
                    StatTile(
                      label: 'Van SKUs',
                      value: '${summary.vanStockSku}',
                      icon: Icons.inventory_2_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SyncCountChip(
                          label: 'Pending',
                          count: summary.syncQueued,
                        ),
                        _SyncCountChip(
                          label: 'Uploading',
                          count: summary.syncInFlight,
                        ),
                        _SyncCountChip(
                          label: 'Conflict',
                          count: summary.syncConflict,
                          emphasize: summary.syncConflict > 0,
                        ),
                        _SyncCountChip(
                          label: 'Failed',
                          count: summary.syncFailed,
                          emphasize: summary.syncFailed > 0,
                        ),
                        _SyncCountChip(
                          label: 'Retry',
                          count: summary.syncRetry,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Route stops',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (_stops.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.route_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No trips yet. Sync after trips are assigned on the site.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._stops.map(
                    (stop) => _StopCard(
                      stop: stop,
                      onCheckIn: () => _setVisit(stop, VisitStatus.checkedIn),
                      onComplete: () => _setVisit(stop, VisitStatus.completed),
                      onSkip: () => _setVisit(stop, VisitStatus.skipped),
                      onSell: () => widget.onSell(stop.customerName),
                      onCollect: () => widget.onCollect(stop.customerName),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SyncCountChip extends StatelessWidget {
  const _SyncCountChip({
    required this.label,
    required this.count,
    this.emphasize = false,
  });

  final String label;
  final int count;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = emphasize ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.stop,
    required this.onCheckIn,
    required this.onComplete,
    required this.onSkip,
    required this.onSell,
    required this.onCollect,
  });

  final RouteStop stop;
  final VoidCallback onCheckIn;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final VoidCallback onSell;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    '${stop.sequence}',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.customerName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        stop.address,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  timeLabel(stop.plannedAt),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 16, color: scheme.secondary),
                const SizedBox(width: 4),
                Text(
                  '${stop.lat.toStringAsFixed(4)}, ${stop.lng.toStringAsFixed(4)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                _VisitChip(status: stop.visitStatus),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (stop.visitStatus == VisitStatus.planned)
                  FilledButton.tonal(
                    onPressed: onCheckIn,
                    child: const Text('Check in'),
                  ),
                if (stop.visitStatus == VisitStatus.checkedIn)
                  FilledButton(
                    onPressed: onComplete,
                    child: const Text('Done'),
                  ),
                FilledButton.tonal(
                  onPressed: onSell,
                  child: const Text('Sell'),
                ),
                OutlinedButton(
                  onPressed: onCollect,
                  child: const Text('Collect'),
                ),
                if (stop.visitStatus != VisitStatus.completed &&
                    stop.visitStatus != VisitStatus.skipped)
                  TextButton(onPressed: onSkip, child: const Text('Skip')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitChip extends StatelessWidget {
  const _VisitChip({required this.status});

  final VisitStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      VisitStatus.planned => ('Planned', Colors.blueGrey),
      VisitStatus.checkedIn => ('Checked in', const Color(0xFFE36414)),
      VisitStatus.completed => ('Done', const Color(0xFF0F4C5C)),
      VisitStatus.skipped => ('Skipped', Colors.brown),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

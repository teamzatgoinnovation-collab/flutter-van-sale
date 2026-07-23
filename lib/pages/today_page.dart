import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../services/aging_service.dart';
import '../services/sync_service.dart';
import '../services/van_sale_policy.dart';
import '../widgets/aging_summary_card.dart';
import '../widgets/widgets.dart';
import 'aging_page.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    required this.sync,
    required this.onSell,
    required this.onCollect,
    this.onOpenMenu,
  });

  final SyncService sync;
  final void Function(String customer, {String? tripId}) onSell;
  final void Function(String customer) onCollect;
  final VoidCallback? onOpenMenu;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _busy = false;
  DaySummary? _summary;
  List<RouteStop> _stops = const [];
  AgingSummary? _aging;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary = await vanSaleRepo.summary();
    final stops = await vanSaleRepo.listStops();
    AgingSummary? aging;
    final session = widget.sync.session;
    if (session.connected) {
      try {
        aging = await AgingService(session).summary();
      } catch (_) {
        aging = await AgingService(session).loadCachedSummary();
      }
    } else {
      aging = await AgingService(session).loadCachedSummary();
    }
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _stops = stops;
      _aging = aging;
    });
  }

  Future<void> _sync() async {
    if (!VanSalePolicy.instance.syncAllowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync disabled — Offline work mode. Switch in Settings.'),
        ),
      );
      return;
    }
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

  Future<({double? lat, double? lng})> _currentGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (lat: null, lng: null);
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return (lat: null, lng: null);
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return (lat: null, lng: null);
    }
  }

  Future<void> _setVisit(RouteStop stop, VisitStatus status) async {
    final gps = status == VisitStatus.checkedIn
        ? await _currentGps()
        : (lat: null, lng: null);
    await vanSaleRepo.updateVisit(
      stop.id,
      status,
      session: widget.sync.session,
      lat: gps.lat,
      lng: gps.lng,
    );
    if (VanSalePolicy.instance.shouldAttemptFlushAfterWrite) {
      try {
        await widget.sync.flush(pullTrips: false);
      } catch (_) {}
    }
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
                  childAspectRatio: 1.25,
                  children: [
                    KpiCard(
                      title: 'Stops done',
                      value: '${summary.stopsDone}/${summary.stopsTotal}',
                      icon: Icons.route_outlined,
                      accentColor: const Color(0xFF0F4C5C),
                      subtitle: summary.stopsTotal > 0
                          ? '${((summary.stopsDone / summary.stopsTotal) * 100).toInt()}% completed'
                          : null,
                    ),
                    KpiCard(
                      title: 'Orders open',
                      value: '${summary.ordersQueued}',
                      icon: Icons.outbox_outlined,
                      accentColor: const Color(0xFFE36414),
                    ),
                    KpiCard(
                      title: 'Collections today',
                      value: money(summary.collectionsToday),
                      icon: Icons.payments_outlined,
                      accentColor: const Color(0xFF2A9D8F),
                    ),
                    KpiCard(
                      title: 'Van SKUs in stock',
                      value: '${summary.vanStockSku}',
                      icon: Icons.inventory_2_outlined,
                      accentColor: Colors.indigo,
                    ),
                  ],
                ),
                if (_aging != null) ...[
                  const SizedBox(height: 12),
                  AgingSummaryCard(
                    summary: _aging!,
                    onOpenDetail: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AgingPage(session: widget.sync.session),
                        ),
                      );
                    },
                  ),
                ],
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
                      onSell: () =>
                          widget.onSell(stop.customerName, tripId: stop.id),
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

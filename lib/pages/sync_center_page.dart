import 'package:flutter/material.dart';

import '../data/van_sale_db.dart';
import '../models/models.dart';
import '../services/prefs.dart';
import '../services/sync_service.dart';
import '../services/van_sale_policy.dart';

/// Manual sync, retry queue, conflict resolution, and sync logs.
class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({super.key, required this.sync});

  final SyncService sync;

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  List<SyncQueueItem> _queue = const [];
  List<Map<String, Object?>> _logs = const [];
  Map<String, int> _counts = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_onSync);
    _reload();
  }

  @override
  void dispose() {
    widget.sync.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (mounted) setState(() {});
    if (!widget.sync.isRunning) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final queue = await VanSaleDb.instance.listQueueByStatuses(const [
      'pending',
      'retry',
      'uploading',
      'failed',
      'conflict',
      'queued',
    ]);
    final logs = await VanSaleDb.instance.listSyncLogs(limit: 80);
    final counts = await VanSaleDb.instance.syncCounts();
    if (!mounted) return;
    setState(() {
      _queue = queue;
      _logs = logs;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _manualSync() async {
    if (!VanSalePolicy.instance.syncAllowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Offline mode — sync disabled. Change work mode in Settings.',
          ),
        ),
      );
      return;
    }
    final result = await widget.sync.flush(mode: SyncMode.manual);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Uploaded ${result.uploaded} · conflicts ${result.conflicts} · '
          'failed ${result.failed}',
        ),
      ),
    );
  }

  Future<void> _retryAll() async {
    if (!VanSalePolicy.instance.syncAllowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Offline mode — sync disabled. Change work mode in Settings.',
          ),
        ),
      );
      return;
    }
    await widget.sync.retryFailed();
    await widget.sync.flush(pullTrips: false, mode: SyncMode.manual);
    await _reload();
  }

  String get _modeLabel => switch (VanSalePrefs.instance.workMode) {
        VanSaleWorkMode.online => 'Online',
        VanSaleWorkMode.offline => 'Offline',
        VanSaleWorkMode.onlineOffline => 'Online+Offline',
      };

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    final theme = Theme.of(context);
    final offlineMode = !VanSalePolicy.instance.syncAllowed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Center'),
        actions: [
          IconButton(
            tooltip: 'Retry failed',
            onPressed: sync.isRunning ? null : _retryAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: sync.isRunning ? null : _manualSync,
            icon: sync.isRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Card(
                  color: offlineMode
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: Icon(
                      offlineMode
                          ? Icons.cloud_off_outlined
                          : Icons.cloud_outlined,
                    ),
                    title: Text('Work mode: $_modeLabel'),
                    subtitle: Text(
                      offlineMode
                          ? 'Offline mode — sync disabled'
                          : 'Sync allowed when signed in',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (sync.isRunning) ...[
                  Text(
                    sync.progressLabel.isEmpty
                        ? 'Syncing…'
                        : sync.progressLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: sync.progressTotal == 0
                        ? null
                        : sync.progressCurrent / sync.progressTotal,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${sync.progressCurrent}/${sync.progressTotal}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(label: 'Pending', count: _counts['pending'] ?? 0),
                    _Chip(label: 'Uploading', count: _counts['uploading'] ?? 0),
                    _Chip(label: 'Retry', count: _counts['retry'] ?? 0),
                    _Chip(
                      label: 'Conflict',
                      count: _counts['conflict'] ?? 0,
                      warn: (_counts['conflict'] ?? 0) > 0,
                    ),
                    _Chip(
                      label: 'Failed',
                      count: _counts['failed'] ?? 0,
                      warn: (_counts['failed'] ?? 0) > 0,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Background sync'),
                  subtitle: Text(
                    offlineMode
                        ? 'Blocked by Offline work mode'
                        : 'Every ~45s while online',
                  ),
                  value: sync.backgroundEnabled && !offlineMode,
                  onChanged: offlineMode
                      ? null
                      : (v) async {
                          await sync.setBackgroundEnabled(v);
                          if (mounted) setState(() {});
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  'Outbox',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_queue.isEmpty)
                  Text(
                    'Queue empty',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ..._queue.map((item) => _QueueTile(
                        item: item,
                        onRetry: () async {
                          if (!VanSalePolicy.instance.syncAllowed) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Offline mode — sync disabled. Change work mode in Settings.',
                                ),
                              ),
                            );
                            return;
                          }
                          await widget.sync.retryFailed(item.id);
                          await widget.sync.flush(
                            pullTrips: false,
                            mode: SyncMode.manual,
                          );
                          await _reload();
                        },
                        onKeepLocal: () async {
                          if (!VanSalePolicy.instance.syncAllowed) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Offline mode — sync disabled. Change work mode in Settings.',
                                ),
                              ),
                            );
                            return;
                          }
                          await widget.sync.resolveConflictKeepLocal(item.id);
                          await widget.sync.flush(
                            pullTrips: false,
                            mode: SyncMode.manual,
                          );
                          await _reload();
                        },
                        onTakeServer: () async {
                          if (!VanSalePolicy.instance.syncAllowed) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Offline mode — sync disabled. Change work mode in Settings.',
                                ),
                              ),
                            );
                            return;
                          }
                          await widget.sync.resolveConflictTakeServer(item.id);
                          await _reload();
                        },
                      )),
                const SizedBox(height: 22),
                Text(
                  'Sync logs',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_logs.isEmpty)
                  Text(
                    'No logs yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ..._logs.map((row) {
                    final level = '${row['level']}';
                    final msg = '${row['message']}';
                    final at = '${row['created_at']}';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        level == 'error'
                            ? Icons.error_outline
                            : level == 'warn'
                                ? Icons.warning_amber_outlined
                                : Icons.info_outline,
                        size: 20,
                      ),
                      title: Text(msg, maxLines: 3, overflow: TextOverflow.ellipsis),
                      subtitle: Text(at),
                    );
                  }),
              ],
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.count, this.warn = false});

  final String label;
  final int count;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label · $count'),
      backgroundColor: warn ? scheme.errorContainer : null,
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.item,
    required this.onRetry,
    required this.onKeepLocal,
    required this.onTakeServer,
  });

  final SyncQueueItem item;
  final VoidCallback onRetry;
  final VoidCallback onKeepLocal;
  final VoidCallback onTakeServer;

  @override
  Widget build(BuildContext context) {
    final isConflict = item.status == 'conflict';
    final isFailed = item.status == 'failed' || item.status == 'retry';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.entityType} · ${item.op}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text('${item.entityId} · ${item.status}'),
            if ((item.lastError ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  item.lastError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (isFailed)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                if (isConflict) ...[
                  TextButton(
                    onPressed: onKeepLocal,
                    child: const Text('Keep local'),
                  ),
                  TextButton(
                    onPressed: onTakeServer,
                    child: const Text('Take server'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

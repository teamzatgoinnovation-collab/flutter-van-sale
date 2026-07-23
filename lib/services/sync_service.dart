import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../customer/repositories/customer_repository.dart';
import '../data/van_sale_db.dart';
import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../product/repositories/product_repository.dart';
import 'prefs.dart';
import 'session.dart';
import 'van_sale_policy.dart';

/// Production sync engine: pending → uploading → uploaded | conflict | failed → retry.
class SyncService extends ChangeNotifier {
  SyncService(
    this.session, {
    VanSaleDb? db,
    VanSaleRepo? repo,
    CustomerRepository? customers,
    ProductRepository? products,
  }) : db = db ?? VanSaleDb.instance,
       repo = repo ?? vanSaleRepo,
       customers = customers ?? customerRepository,
       products = products ?? productRepository {
    applyPrefs();
  }

  final VanSaleSession session;
  final VanSaleDb db;
  final VanSaleRepo repo;
  final CustomerRepository customers;
  final ProductRepository products;

  static const batchMethod = 'zatgo_core.api.v1.sync.batch.batch';
  static const _backgroundInterval = Duration(seconds: 45);

  bool _running = false;
  bool get isRunning => _running;

  /// In-flight flush so concurrent callers await the same result (no stale counts).
  Future<SyncFlushResult>? _inFlight;

  int progressCurrent = 0;
  int progressTotal = 0;
  String progressLabel = '';
  SyncFlushResult? lastResult;
  Timer? _bgTimer;
  bool backgroundEnabled = true;

  /// Load persisted background sync + respect Offline work mode.
  void applyPrefs() {
    backgroundEnabled = VanSalePolicy.instance.backgroundSyncDesired;
  }

  Future<void> setBackgroundEnabled(bool value) async {
    await VanSalePrefs.instance.setBackgroundSync(value);
    backgroundEnabled = VanSalePolicy.instance.backgroundSyncDesired;
    notifyListeners();
    if (backgroundEnabled && session.connected) {
      startBackgroundSync();
    } else {
      stopBackgroundSync();
    }
  }

  void startBackgroundSync() {
    _bgTimer?.cancel();
    applyPrefs();
    if (!backgroundEnabled) return;
    if (!VanSalePolicy.instance.syncAllowed) return;
    _bgTimer = Timer.periodic(_backgroundInterval, (_) {
      if (!_running && session.connected && VanSalePolicy.instance.syncAllowed) {
        unawaited(flush(pullTrips: true, mode: SyncMode.background));
      }
    });
  }

  void stopBackgroundSync() {
    _bgTimer?.cancel();
    _bgTimer = null;
  }

  @override
  void dispose() {
    stopBackgroundSync();
    super.dispose();
  }

  Future<SyncFlushResult> flush({
    bool pullTrips = true,
    SyncMode mode = SyncMode.manual,
    bool useBatch = true,
    int continueOnFailure = 1,
  }) async {
    if (!VanSalePolicy.instance.syncAllowed) {
      await db.addSyncLog(
        level: 'info',
        message: 'Sync skipped (Offline work mode)',
      );
      return const SyncFlushResult();
    }
    if (!session.connected) {
      return const SyncFlushResult();
    }
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    final quietPull = mode == SyncMode.background;
    final future = _runFlush(
      pullTrips: pullTrips,
      quietPull: quietPull,
      useBatch: useBatch,
      continueOnFailure: continueOnFailure,
      mode: mode,
    );
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }
  }

  Future<SyncFlushResult> _runFlush({
    required bool pullTrips,
    required bool quietPull,
    required bool useBatch,
    required int continueOnFailure,
    required SyncMode mode,
  }) async {
    _running = true;
    progressCurrent = 0;
    progressTotal = 0;
    // Background: no banner for catalog pull; only show when uploading.
    progressLabel = quietPull ? '' : 'Syncing…';
    if (!quietPull) notifyListeners();

    await db.addSyncLog(
      level: 'info',
      message: 'Sync started (${mode.name})',
    );

    try {
      await customers.loadDefaults(session);
      await products.loadDefaults(session);
      await db.requeueInFlightAsQueued();

      final pending = await db.listQueueByStatuses(const [
        'pending',
        'retry',
        'queued',
      ]);
      final showUi = !quietPull || pending.isNotEmpty;
      progressTotal = pending.length + (pullTrips && !quietPull ? 1 : 0);
      if (showUi && pending.isNotEmpty) {
        if (quietPull) progressLabel = 'Background sync…';
        notifyListeners();
      }

      var uploaded = 0;
      var failed = 0;
      var conflicts = 0;
      var retried = 0;

      if (useBatch) {
        final master = pending
            .where(
              (e) => e.entityType == 'customer' || e.entityType == 'product',
            )
            .toList();
        final other = pending
            .where(
              (e) => e.entityType != 'customer' && e.entityType != 'product',
            )
            .toList();

        for (var i = 0; i < master.length; i += 20) {
          final chunk = master.sublist(i, (i + 20).clamp(0, master.length));
          final batchResult = await _flushBatch(chunk);
          uploaded += batchResult.uploaded;
          failed += batchResult.failed;
          conflicts += batchResult.conflicts;
          progressCurrent =
              (progressCurrent + chunk.length).clamp(0, progressTotal);
          if (showUi) {
            progressLabel = 'Batch $progressCurrent/$progressTotal';
            notifyListeners();
          }
        }

        for (final item in other) {
          if (showUi) {
            progressLabel = '${item.entityType} ${item.op}';
            notifyListeners();
          }
          final ok = await _flushOne(
            item,
            continueOnFailure: continueOnFailure == 1,
          );
          if (ok == _FlushOutcome.uploaded) uploaded++;
          if (ok == _FlushOutcome.failed) failed++;
          if (ok == _FlushOutcome.conflict) conflicts++;
          progressCurrent++;
          if (showUi) notifyListeners();
          if (ok == _FlushOutcome.failed && continueOnFailure != 1) break;
        }
      } else {
        while (true) {
          final item = await db.claimNext();
          if (item == null) break;
          if (showUi) {
            progressLabel = '${item.entityType} ${item.op}';
            notifyListeners();
          }
          final ok = await _flushOne(item, continueOnFailure: true);
          if (ok == _FlushOutcome.uploaded) uploaded++;
          if (ok == _FlushOutcome.failed) failed++;
          if (ok == _FlushOutcome.conflict) conflicts++;
          progressCurrent++;
          if (showUi) notifyListeners();
        }
      }

      if (pullTrips) {
        // Catalog / trips pull is always silent — no banner label.
        await repo.refreshFromErpnext(session);
        await products.refreshFromErp(session);
        await customers.refreshFromErp(session);
        if (!quietPull) {
          progressCurrent = progressTotal;
          notifyListeners();
        }
      }

      final result = SyncFlushResult(
        uploaded: uploaded,
        failed: failed,
        conflicts: conflicts,
        retried: retried,
        processed: uploaded,
      );
      lastResult = result;
      await db.addSyncLog(
        level: failed > 0 || conflicts > 0 ? 'warn' : 'info',
        message:
            'Sync done · uploaded $uploaded · conflicts $conflicts · failed $failed',
      );
      return result;
    } catch (e) {
      await db.addSyncLog(level: 'error', message: 'Sync crashed: $e');
      rethrow;
    } finally {
      _running = false;
      progressLabel = '';
      notifyListeners();
    }
  }

  Future<SyncFlushResult> _flushBatch(List<SyncQueueItem> items) async {
    if (items.isEmpty) return const SyncFlushResult();
    final ops = <Map<String, dynamic>>[];
    for (final item in items) {
      await db.database.then(
        (d) => d.update(
          'sync_queue',
          {'status': 'uploading', 'attempts': item.attempts + 1},
          where: 'id = ?',
          whereArgs: [item.id],
        ),
      );
      await _markEntityStatus(item, SyncStatus.uploading);
      final args = await _resolveArgs(item);
      ops.add({
        'id': item.id,
        'entity_type': item.entityType,
        'op': item.op,
        'client_id': item.clientId,
        'base_modified': args['base_modified'],
        'force': args['force'] ?? 0,
        'payload': args['customer'] ?? args['item'] ?? args,
        'contact': args['contact'],
        'address': args['address'],
        'attachments': args['attachments'],
      });
    }

    try {
      final env = await session.store.callMethod(
        batchMethod,
        args: {'operations': jsonEncode(ops)},
      );
      final data = env.data;
      final results = <dynamic>[];
      if (data is Map && data['results'] is List) {
        results.addAll(data['results'] as List);
      }

      var uploaded = 0;
      var failed = 0;
      var conflicts = 0;

      for (final raw in results) {
        if (raw is! Map) continue;
        final id = '${raw['id']}';
        SyncQueueItem? matched;
        for (final e in items) {
          if (e.id == id) {
            matched = e;
            break;
          }
        }
        if (matched == null) {
          await db.addSyncLog(
            level: 'warn',
            message: 'Batch result id unmatched: $id',
            queueId: id.isEmpty ? null : id,
          );
          continue;
        }
        final item = matched;
        if (raw['conflict'] == true) {
          conflicts++;
          await db.markQueueConflict(
            id,
            '${raw['meta']?['message'] ?? 'Conflict'}',
          );
          await _markEntityStatus(item, SyncStatus.conflict, error: 'Conflict');
          await db.addSyncLog(
            level: 'warn',
            message: 'Conflict on ${item.entityType} ${item.entityId}',
            entityType: item.entityType,
            entityId: item.entityId,
            queueId: id,
          );
          continue;
        }
        if (raw['success'] == true) {
          final erpName = _extractErpName(item, raw['data']);
          if (erpName == null || erpName.isEmpty) {
            failed++;
            const err = 'Server ack missing name';
            await db.markQueueFailed(id, err);
            await _markEntityStatus(item, SyncStatus.failed, error: err);
            await db.addSyncLog(
              level: 'error',
              message: err,
              entityType: item.entityType,
              entityId: item.entityId,
              queueId: id,
            );
            continue;
          }
          uploaded++;
          final modified = raw['data'] is Map
              ? '${(raw['data'] as Map)['modified'] ?? ''}'
              : null;
          await _markEntitySynced(
            item,
            erpName,
            erpModified: (modified == null || modified.isEmpty)
                ? null
                : modified,
            data: raw['data'],
          );
          await db.markQueueDone(id);
          await db.addSyncLog(
            level: 'info',
            message: 'Uploaded ${item.entityType} → $erpName',
            entityType: item.entityType,
            entityId: item.entityId,
            queueId: id,
          );
        } else {
          failed++;
          final err = '${raw['error'] ?? 'Batch op failed'}';
          await db.markQueueFailed(id, err);
          await _markEntityStatus(item, SyncStatus.failed, error: err);
          await db.addSyncLog(
            level: 'error',
            message: err,
            entityType: item.entityType,
            entityId: item.entityId,
            queueId: id,
          );
        }
      }
      return SyncFlushResult(
        uploaded: uploaded,
        failed: failed,
        conflicts: conflicts,
        processed: uploaded,
      );
    } catch (e) {
      // Fall back to one-by-one
      await db.addSyncLog(
        level: 'warn',
        message: 'Batch failed, falling back: $e',
      );
      var uploaded = 0;
      var failed = 0;
      var conflicts = 0;
      for (final item in items) {
        final outcome = await _flushOne(item, continueOnFailure: true);
        if (outcome == _FlushOutcome.uploaded) uploaded++;
        if (outcome == _FlushOutcome.failed) failed++;
        if (outcome == _FlushOutcome.conflict) conflicts++;
      }
      return SyncFlushResult(
        uploaded: uploaded,
        failed: failed,
        conflicts: conflicts,
        processed: uploaded,
      );
    }
  }

  Future<_FlushOutcome> _flushOne(
    SyncQueueItem item, {
    required bool continueOnFailure,
  }) async {
    try {
      await _markEntityStatus(item, SyncStatus.uploading);
      final args = await _resolveArgs(item);
      final env = await session.store.callMethod(item.method, args: args);
      final meta = env.meta;
      final Map<String, dynamic>? metaMap = meta is Map
          ? Map<String, dynamic>.from(meta as Map)
          : null;
      final conflict = metaMap != null && metaMap['conflict'] == true;
      if (conflict) {
        await db.markQueueConflict(
          item.id,
          '${metaMap['message'] ?? 'Conflict'}',
        );
        await _markEntityStatus(item, SyncStatus.conflict, error: 'Conflict');
        await db.addSyncLog(
          level: 'warn',
          message: 'Conflict ${item.entityType}/${item.entityId}',
          queueId: item.id,
          entityType: item.entityType,
          entityId: item.entityId,
        );
        return _FlushOutcome.conflict;
      }
      final erpName = _extractErpName(item, env.data);
      if (erpName == null || erpName.isEmpty) {
        throw StateError('Server ack missing name for ${item.method}');
      }
      String? modified;
      if (env.data is Map) {
        modified = '${(env.data as Map)['modified'] ?? ''}';
        if (modified.isEmpty) modified = null;
      }
      await _markEntitySynced(
        item,
        erpName,
        erpModified: modified,
        data: env.data,
      );
      await db.markQueueDone(item.id);
      await db.addSyncLog(
        level: 'info',
        message: 'Uploaded ${item.entityType} → $erpName',
        queueId: item.id,
        entityType: item.entityType,
        entityId: item.entityId,
      );
      return _FlushOutcome.uploaded;
    } catch (e) {
      await db.markQueueFailed(item.id, e.toString());
      await _markEntityStatus(item, SyncStatus.failed, error: e.toString());
      await db.addSyncLog(
        level: 'error',
        message: e.toString(),
        queueId: item.id,
        entityType: item.entityType,
        entityId: item.entityId,
      );
      return _FlushOutcome.failed;
    }
  }

  Future<Map<String, dynamic>> _resolveArgs(SyncQueueItem item) async {
    if (item.entityType == 'customer' &&
        item.method == CustomerApiMethods.sync) {
      final localId = '${item.args['local_id'] ?? item.entityId}';
      final args = await customers.buildSyncArgs(localId);
      args['op'] = item.op;
      args['force'] = item.args['force'] ?? 0;
      final modified = await _readErpModified('customers', localId);
      if (modified != null) args['base_modified'] = modified;
      return args;
    }
    if (item.entityType == 'product' &&
        item.method == ProductApiMethods.sync) {
      final localId = '${item.args['local_id'] ?? item.entityId}';
      final args = await products.buildSyncArgs(localId);
      args['op'] = item.op;
      args['force'] = item.args['force'] ?? 0;
      final modified = await _readErpModified('products', localId);
      if (modified != null) args['base_modified'] = modified;
      return args;
    }
    if (item.entityType == 'van_order') {
      final args = Map<String, dynamic>.from(item.args);
      final customer = '${args['customer'] ?? ''}'.trim();
      if (customer.isNotEmpty) {
        // Prefer latest ERP customer id if local row synced after enqueue.
        try {
          final page = await customers.search(query: customer, limit: 8);
          for (final c in page.items) {
            final erp = (c.erpName ?? '').trim();
            if (erp.isEmpty) continue;
            if (c.customerName == customer ||
                c.displayName == customer ||
                erp == customer) {
              args['customer'] = erp;
              break;
            }
          }
        } catch (_) {}
      }
      return args;
    }
    return item.args;
  }

  Future<String?> _readErpModified(String table, String id) async {
    final database = await db.database;
    try {
      final rows = await database.query(
        table,
        columns: ['erp_modified'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final v = rows.first['erp_modified'];
      if (v == null || '$v'.isEmpty) return null;
      return '$v';
    } catch (_) {
      return null;
    }
  }

  Future<void> retryFailed([String? queueId]) async {
    if (queueId != null) {
      await db.requeueFailed(queueId);
      await db.addSyncLog(level: 'info', message: 'Retry queued $queueId');
    } else {
      final n = await db.requeueAllFailed();
      await db.addSyncLog(level: 'info', message: 'Retry queued $n items');
    }
    notifyListeners();
  }

  Future<void> resolveConflictKeepLocal(String queueId) async {
    final database = await db.database;
    final rows = await database.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final args = Map<String, dynamic>.from(
      jsonDecode('${rows.first['args_json']}') as Map? ?? {},
    );
    args['force'] = 1;
    await database.update(
      'sync_queue',
      {
        'args_json': jsonEncode(args),
        'status': 'retry',
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
    await db.addSyncLog(
      level: 'info',
      message: 'Conflict resolved: keep local ($queueId)',
      queueId: queueId,
    );
    notifyListeners();
  }

  Future<void> resolveConflictTakeServer(String queueId) async {
    // Drop local pending write; next pull will refresh.
    await db.markQueueDone(queueId);
    await db.addSyncLog(
      level: 'info',
      message: 'Conflict resolved: take server ($queueId)',
      queueId: queueId,
    );
    if (session.connected) {
      await products.refreshFromErp(session);
      await repo.refreshFromErpnext(session);
    }
    notifyListeners();
  }

  Future<void> _markEntitySynced(
    SyncQueueItem item,
    String erpName, {
    String? erpModified,
    Object? data,
  }) async {
    switch (item.entityType) {
      case 'van_order':
        double? amount;
        if (data is Map) {
          amount = (data['amount'] as num?)?.toDouble() ??
              (data['grand_total'] as num?)?.toDouble();
        }
        await db.setOrderSync(
          id: item.entityId,
          status: SyncStatus.uploaded,
          erpName: erpName,
          amount: amount,
        );
      case 'collection':
        await db.setCollectionSync(
          id: item.entityId,
          status: SyncStatus.uploaded,
          erpName: erpName,
        );
      case 'customer':
        await db.setCustomerSync(
          id: item.entityId,
          status: SyncStatus.uploaded,
          erpName: erpName,
          erpModified: erpModified,
        );
      case 'product':
        await db.setProductSync(
          id: item.entityId,
          status: SyncStatus.uploaded,
          erpName: erpName,
          erpModified: erpModified,
        );
      default:
        break;
    }
  }

  Future<void> _markEntityStatus(
    SyncQueueItem item,
    SyncStatus status, {
    String? error,
  }) async {
    switch (item.entityType) {
      case 'van_order':
        await db.setOrderSync(id: item.entityId, status: status);
      case 'collection':
        await db.setCollectionSync(id: item.entityId, status: status);
      case 'customer':
        await db.setCustomerSync(
          id: item.entityId,
          status: status,
          lastError: error,
        );
      case 'product':
        await db.setProductSync(
          id: item.entityId,
          status: status,
          lastError: error,
        );
      default:
        break;
    }
  }

  String? _extractErpName(SyncQueueItem item, Object? data) {
    if (item.entityType == 'customer') {
      return customers.extractErpName(data);
    }
    if (item.entityType == 'product') {
      return products.extractErpName(data);
    }
    if (data is Map) {
      final name = data['erp_name'] ?? data['name'] ?? data['id'];
      if (name != null && '$name'.isNotEmpty) return '$name';
    }
    return null;
  }
}

enum SyncMode { manual, background, afterWrite }

enum _FlushOutcome { uploaded, failed, conflict }

class SyncFlushResult {
  const SyncFlushResult({
    this.uploaded = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.retried = 0,
    this.processed = 0,
    // legacy aliases
    this.awaitingErp = 0,
  });

  final int uploaded;
  final int failed;
  final int conflicts;
  final int retried;
  final int processed;
  final int awaitingErp;
}

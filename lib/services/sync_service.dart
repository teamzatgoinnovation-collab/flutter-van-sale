import '../data/van_sale_db.dart';
import '../data/van_sale_repo.dart';
import '../models/models.dart';
import 'session.dart';

/// Idempotent outbox flush + trip pull.
class SyncService {
  SyncService(this.session, {VanSaleDb? db, VanSaleRepo? repo})
      : db = db ?? VanSaleDb.instance,
        repo = repo ?? vanSaleRepo;

  final VanSaleSession session;
  final VanSaleDb db;
  final VanSaleRepo repo;

  /// Returns how many queue rows reached a terminal soft/hard outcome this pass.
  Future<SyncFlushResult> flush({bool pullTrips = true}) async {
    if (!session.connected && !session.allowMockWithoutLogin) {
      return const SyncFlushResult(processed: 0, awaitingErp: 0, failed: 0);
    }

    await db.requeueInFlightAsQueued();

    var processed = 0;
    var awaiting = 0;
    var failed = 0;

    if (session.connected) {
      while (true) {
        final item = await db.claimNext();
        if (item == null) break;

        try {
          final env = await session.store.callMethod(
            item.method,
            args: item.args,
          );
          final erpName = _extractErpName(env.data) ??
              _extractErpName(item.args) ??
              'ERP-${item.clientId.substring(0, 8)}';
          await _markEntitySynced(item, erpName);
          await db.markQueueDone(item.id);
          processed++;
        } catch (e) {
          final msg = e.toString();
          if (_isMissingApi(msg)) {
            await _markEntityAwaitingErp(item);
            await db.markQueueAwaitingErp(item.id, error: msg);
            awaiting++;
            processed++;
            // Keep flushing remaining rows when API is simply not deployed yet.
            continue;
          }
          await _markEntityFailed(item);
          await db.markQueueFailed(item.id, msg);
          failed++;
          break;
        }
      }

      if (pullTrips) {
        await repo.refreshFromErpnext(session);
      }
    }

    return SyncFlushResult(
      processed: processed,
      awaitingErp: awaiting,
      failed: failed,
    );
  }

  Future<void> retryFailed(String queueId) async {
    await db.requeueFailed(queueId);
  }

  Future<void> _markEntitySynced(SyncQueueItem item, String erpName) async {
    switch (item.entityType) {
      case 'van_order':
        await db.setOrderSync(
          id: item.entityId,
          status: SyncStatus.synced,
          erpName: erpName,
        );
      case 'collection':
        await db.setCollectionSync(
          id: item.entityId,
          status: SyncStatus.synced,
          erpName: erpName,
        );
      default:
        break;
    }
  }

  Future<void> _markEntityAwaitingErp(SyncQueueItem item) async {
    switch (item.entityType) {
      case 'van_order':
        await db.setOrderSync(
          id: item.entityId,
          status: SyncStatus.awaitingErp,
        );
      case 'collection':
        await db.setCollectionSync(
          id: item.entityId,
          status: SyncStatus.awaitingErp,
        );
      default:
        break;
    }
  }

  Future<void> _markEntityFailed(SyncQueueItem item) async {
    switch (item.entityType) {
      case 'van_order':
        await db.setOrderSync(id: item.entityId, status: SyncStatus.failed);
      case 'collection':
        await db.setCollectionSync(
          id: item.entityId,
          status: SyncStatus.failed,
        );
      default:
        break;
    }
  }

  bool _isMissingApi(String message) {
    final m = message.toLowerCase();
    return m.contains('not found') ||
        m.contains('does not exist') ||
        m.contains('attributeerror') ||
        m.contains('no module') ||
        m.contains('stub') ||
        m.contains('404') ||
        m.contains('doctypes') ||
        m.contains('permissionerror');
  }

  String? _extractErpName(Object? data) {
    if (data is Map) {
      final name = data['name'] ?? data['erp_name'] ?? data['id'];
      if (name != null && '$name'.isNotEmpty) return '$name';
    }
    return null;
  }
}

class SyncFlushResult {
  const SyncFlushResult({
    required this.processed,
    required this.awaitingErp,
    required this.failed,
  });

  final int processed;
  final int awaitingErp;
  final int failed;
}

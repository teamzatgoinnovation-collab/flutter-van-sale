import '../data/van_sale_db.dart';
import '../data/van_sale_repo.dart';
import '../models/models.dart';
import 'session.dart';

/// Idempotent outbox flush + ERP pull (no soft-ack for go_van writes).
class SyncService {
  SyncService(this.session, {VanSaleDb? db, VanSaleRepo? repo})
    : db = db ?? VanSaleDb.instance,
      repo = repo ?? vanSaleRepo;

  final VanSaleSession session;
  final VanSaleDb db;
  final VanSaleRepo repo;

  Future<SyncFlushResult> flush({bool pullTrips = true}) async {
    if (!session.connected) {
      return const SyncFlushResult(processed: 0, awaitingErp: 0, failed: 0);
    }

    await db.requeueInFlightAsQueued();

    var processed = 0;
    var failed = 0;

    while (true) {
      final item = await db.claimNext();
      if (item == null) break;

      try {
        final env = await session.store.callMethod(
          item.method,
          args: item.args,
        );
        final erpName = _extractErpName(env.data);
        if (erpName == null || erpName.isEmpty) {
          throw StateError('ERP ack missing name for ${item.method}');
        }
        await _markEntitySynced(item, erpName);
        await db.markQueueDone(item.id);
        processed++;
      } catch (e) {
        await _markEntityFailed(item);
        await db.markQueueFailed(item.id, e.toString());
        failed++;
        break;
      }
    }

    if (pullTrips) {
      await repo.refreshFromErpnext(session);
    }

    return SyncFlushResult(
      processed: processed,
      awaitingErp: 0,
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

  String? _extractErpName(Object? data) {
    if (data is Map) {
      final name = data['erp_name'] ?? data['name'] ?? data['id'];
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

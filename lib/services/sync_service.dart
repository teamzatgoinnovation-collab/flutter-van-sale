import '../customer/repositories/customer_repository.dart';
import '../data/van_sale_db.dart';
import '../data/van_sale_repo.dart';
import '../models/models.dart';
import '../product/repositories/product_repository.dart';
import 'session.dart';

/// Idempotent outbox flush + ERP pull (customer → product → sales).
class SyncService {
  SyncService(
    this.session, {
    VanSaleDb? db,
    VanSaleRepo? repo,
    CustomerRepository? customers,
    ProductRepository? products,
  }) : db = db ?? VanSaleDb.instance,
       repo = repo ?? vanSaleRepo,
       customers = customers ?? customerRepository,
       products = products ?? productRepository;

  final VanSaleSession session;
  final VanSaleDb db;
  final VanSaleRepo repo;
  final CustomerRepository customers;
  final ProductRepository products;

  Future<SyncFlushResult> flush({bool pullTrips = true}) async {
    if (!session.connected) {
      return const SyncFlushResult(processed: 0, awaitingErp: 0, failed: 0);
    }

    await customers.loadDefaults(session);
    await products.loadDefaults(session);
    await db.requeueInFlightAsQueued();

    var processed = 0;
    var failed = 0;

    while (true) {
      final item = await db.claimNext();
      if (item == null) break;

      try {
        final args = await _resolveArgs(item);
        final env = await session.store.callMethod(
          item.method,
          args: args,
        );
        final erpName = _extractErpName(item, env.data);
        if (erpName == null || erpName.isEmpty) {
          throw StateError('ERP ack missing name for ${item.method}');
        }
        await _markEntitySynced(item, erpName);
        await db.markQueueDone(item.id);
        processed++;
      } catch (e) {
        await _markEntityFailed(item, e.toString());
        await db.markQueueFailed(item.id, e.toString());
        failed++;
        break;
      }
    }

    if (pullTrips) {
      await repo.refreshFromErpnext(session);
      await products.refreshFromErp(session);
    }

    return SyncFlushResult(
      processed: processed,
      awaitingErp: 0,
      failed: failed,
    );
  }

  Future<Map<String, dynamic>> _resolveArgs(SyncQueueItem item) async {
    if (item.entityType == 'customer' &&
        item.method == CustomerApiMethods.sync) {
      final localId = '${item.args['local_id'] ?? item.entityId}';
      return customers.buildSyncArgs(localId);
    }
    if (item.entityType == 'product' &&
        item.method == ProductApiMethods.sync) {
      final localId = '${item.args['local_id'] ?? item.entityId}';
      return products.buildSyncArgs(localId);
    }
    return item.args;
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
      case 'customer':
        await db.setCustomerSync(
          id: item.entityId,
          status: SyncStatus.synced,
          erpName: erpName,
        );
      case 'product':
        await db.setProductSync(
          id: item.entityId,
          status: SyncStatus.synced,
          erpName: erpName,
        );
      default:
        break;
    }
  }

  Future<void> _markEntityFailed(SyncQueueItem item, String error) async {
    switch (item.entityType) {
      case 'van_order':
        await db.setOrderSync(id: item.entityId, status: SyncStatus.failed);
      case 'collection':
        await db.setCollectionSync(
          id: item.entityId,
          status: SyncStatus.failed,
        );
      case 'customer':
        await db.setCustomerSync(
          id: item.entityId,
          status: SyncStatus.failed,
          lastError: error,
        );
      case 'product':
        await db.setProductSync(
          id: item.entityId,
          status: SyncStatus.failed,
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

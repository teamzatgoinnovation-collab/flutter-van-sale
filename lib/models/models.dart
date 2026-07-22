enum SyncStatus { queued, inFlight, awaitingErp, synced, failed }

enum VisitStatus { planned, checkedIn, completed, skipped }

class RouteStop {
  const RouteStop({
    required this.id,
    required this.customerName,
    required this.address,
    required this.sequence,
    required this.lat,
    required this.lng,
    this.plannedAt,
    this.visitStatus = VisitStatus.planned,
  });

  final String id;
  final String customerName;
  final String address;
  final int sequence;
  final double lat;
  final double lng;
  final DateTime? plannedAt;
  final VisitStatus visitStatus;

  RouteStop copyWith({VisitStatus? visitStatus}) {
    return RouteStop(
      id: id,
      customerName: customerName,
      address: address,
      sequence: sequence,
      lat: lat,
      lng: lng,
      plannedAt: plannedAt,
      visitStatus: visitStatus ?? this.visitStatus,
    );
  }
}

class OrderLine {
  const OrderLine({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.unitPrice,
  });

  final String itemCode;
  final String itemName;
  final double qty;
  final double unitPrice;

  double get amount => qty * unitPrice;

  Map<String, dynamic> toJson() => {
        'item_code': itemCode,
        'item_name': itemName,
        'qty': qty,
        'unit_price': unitPrice,
        'amount': amount,
      };

  factory OrderLine.fromJson(Map<String, dynamic> json) {
    return OrderLine(
      itemCode: '${json['item_code'] ?? ''}',
      itemName: '${json['item_name'] ?? ''}',
      qty: (json['qty'] as num?)?.toDouble() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class VanOrder {
  const VanOrder({
    required this.id,
    required this.clientId,
    required this.customerName,
    required this.lines,
    required this.amount,
    required this.createdAt,
    required this.syncStatus,
    this.erpName,
  });

  final String id;
  final String clientId;
  final String customerName;
  final List<OrderLine> lines;
  final double amount;
  final DateTime createdAt;
  final SyncStatus syncStatus;
  final String? erpName;

  String get itemsLabel {
    if (lines.isEmpty) return 'No lines';
    if (lines.length == 1) {
      final l = lines.first;
      return '${l.qty.toStringAsFixed(l.qty % 1 == 0 ? 0 : 1)}× ${l.itemName}';
    }
    return '${lines.length} SKUs';
  }
}

class Collection {
  const Collection({
    required this.id,
    required this.clientId,
    required this.customerName,
    required this.amount,
    required this.method,
    required this.collectedAt,
    required this.syncStatus,
    this.erpName,
  });

  final String id;
  final String clientId;
  final String customerName;
  final double amount;
  final String method;
  final DateTime collectedAt;
  final SyncStatus syncStatus;
  final String? erpName;
}

class StockLine {
  const StockLine({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.uom,
    required this.unitPrice,
  });

  final String itemCode;
  final String itemName;
  final double qty;
  final String uom;
  final double unitPrice;

  StockLine copyWith({double? qty}) {
    return StockLine(
      itemCode: itemCode,
      itemName: itemName,
      qty: qty ?? this.qty,
      uom: uom,
      unitPrice: unitPrice,
    );
  }
}

class DaySummary {
  const DaySummary({
    required this.stopsTotal,
    required this.stopsDone,
    required this.ordersQueued,
    required this.collectionsToday,
    required this.vanStockSku,
    required this.syncQueued,
    required this.syncInFlight,
    required this.syncAwaitingErp,
    required this.syncFailed,
  });

  final int stopsTotal;
  final int stopsDone;
  final int ordersQueued;
  final double collectionsToday;
  final int vanStockSku;
  final int syncQueued;
  final int syncInFlight;
  final int syncAwaitingErp;
  final int syncFailed;
}

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.clientId,
    required this.entityType,
    required this.entityId,
    required this.op,
    required this.method,
    required this.args,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });

  final String id;
  final String clientId;
  final String entityType;
  final String entityId;
  final String op;
  final String method;
  final Map<String, dynamic> args;
  final String status;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;
}

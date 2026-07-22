import '../services/van_sale_api_methods.dart';
import '../services/session.dart';
import '../services/van_sale_context.dart';

/// Server-backed admin reads (all vans).
class VanSaleAdminApi {
  VanSaleAdminApi(this.session);

  final VanSaleSession session;

  Future<List<VanSaleProfile>> listUsers() async {
    final env = await session.store.callMethod(
      VanSaleApiMethods.adminUsers,
      args: {'page': 1, 'page_size': 100},
    );
    final rows = _asList(env.data);
    return [
      for (final raw in rows)
        if (raw is Map)
          VanSaleProfile.fromJson(Map<String, dynamic>.from(raw)),
    ];
  }

  Future<Map<String, dynamic>> summary({
    String? salesUser,
    String? warehouse,
    String? vehicle,
    String? routeTitle,
    String? date,
  }) async {
    final env = await session.store.callMethod(
      VanSaleApiMethods.adminSummary,
      args: {
        if (salesUser != null && salesUser.isNotEmpty) 'sales_user': salesUser,
        if (warehouse != null && warehouse.isNotEmpty) 'warehouse': warehouse,
        if (vehicle != null && vehicle.isNotEmpty) 'vehicle': vehicle,
        if (routeTitle != null && routeTitle.isNotEmpty)
          'route_title': routeTitle,
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final data = env.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<List<Map<String, dynamic>>> listTrips({
    String? salesUser,
    String? warehouse,
    String? vehicle,
    String? routeTitle,
    String? date,
  }) async {
    final env = await session.store.callMethod(
      VanSaleApiMethods.tripsList,
      args: {
        'page': 1,
        'page_size': 200,
        if (salesUser != null && salesUser.isNotEmpty) 'sales_user': salesUser,
        if (warehouse != null && warehouse.isNotEmpty) 'warehouse': warehouse,
        if (vehicle != null && vehicle.isNotEmpty) 'vehicle': vehicle,
        if (routeTitle != null && routeTitle.isNotEmpty)
          'route_title': routeTitle,
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    return [
      for (final raw in _asList(env.data))
        if (raw is Map) Map<String, dynamic>.from(raw),
    ];
  }

  Future<List<Map<String, dynamic>>> listOrders({
    String? salesUser,
    String? warehouse,
    String? date,
  }) async {
    final env = await session.store.callMethod(
      VanSaleApiMethods.ordersList,
      args: {
        'page': 1,
        'page_size': 100,
        if (salesUser != null && salesUser.isNotEmpty) 'sales_user': salesUser,
        if (warehouse != null && warehouse.isNotEmpty) 'warehouse': warehouse,
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    return [
      for (final raw in _asList(env.data))
        if (raw is Map) Map<String, dynamic>.from(raw),
    ];
  }

  Future<List<Map<String, dynamic>>> listCollections({
    String? salesUser,
    String? date,
  }) async {
    final env = await session.store.callMethod(
      VanSaleApiMethods.collectionsList,
      args: {
        'page': 1,
        'page_size': 100,
        if (salesUser != null && salesUser.isNotEmpty) 'sales_user': salesUser,
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    return [
      for (final raw in _asList(env.data))
        if (raw is Map) Map<String, dynamic>.from(raw),
    ];
  }

  List _asList(Object? data) {
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    return const [];
  }
}

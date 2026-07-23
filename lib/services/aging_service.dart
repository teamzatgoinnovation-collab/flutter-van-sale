import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'prefs.dart';
import 'session.dart';
import 'van_sale_api_methods.dart';

class AgingBuckets {
  const AgingBuckets({
    this.current = 0,
    this.d130 = 0,
    this.d3160 = 0,
    this.d6190 = 0,
    this.d91120 = 0,
    this.d120Plus = 0,
    this.total = 0,
    this.overdue = 0,
  });

  final double current;
  final double d130;
  final double d3160;
  final double d6190;
  final double d91120;
  final double d120Plus;
  final double total;
  final double overdue;

  factory AgingBuckets.fromJson(Map<String, dynamic> j) {
    double n(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return AgingBuckets(
      current: n('current'),
      d130: n('d_1_30'),
      d3160: n('d_31_60'),
      d6190: n('d_61_90'),
      d91120: n('d_91_120'),
      d120Plus: n('d_120_plus'),
      total: n('total'),
      overdue: n('overdue'),
    );
  }

  Map<String, dynamic> toJson() => {
    'current': current,
    'd_1_30': d130,
    'd_31_60': d3160,
    'd_61_90': d6190,
    'd_91_120': d91120,
    'd_120_plus': d120Plus,
    'total': total,
    'overdue': overdue,
  };
}

class AgingSummary {
  const AgingSummary({
    required this.asOf,
    required this.buckets,
    required this.customers,
    required this.customerCount,
    this.fromCache = false,
  });

  final String asOf;
  final AgingBuckets buckets;
  final List<Map<String, dynamic>> customers;
  final int customerCount;
  final bool fromCache;

  factory AgingSummary.fromJson(
    Map<String, dynamic> j, {
    bool fromCache = false,
  }) {
    final rawBuckets = j['buckets'];
    return AgingSummary(
      asOf: '${j['as_of'] ?? ''}',
      buckets: rawBuckets is Map
          ? AgingBuckets.fromJson(Map<String, dynamic>.from(rawBuckets))
          : const AgingBuckets(),
      customers: [
        for (final raw in (j['customers'] as List? ?? const []))
          if (raw is Map) Map<String, dynamic>.from(raw),
      ],
      customerCount: (j['customer_count'] as num?)?.toInt() ?? 0,
      fromCache: fromCache,
    );
  }

  Map<String, dynamic> toJson() => {
    'as_of': asOf,
    'buckets': buckets.toJson(),
    'customers': customers,
    'customer_count': customerCount,
  };
}

/// Pulls ERPNext AR aging via go_van and caches the last successful summary.
class AgingService {
  AgingService(this.session);

  final VanSaleSession session;

  static const _cacheKey = 'van_sale.aging_summary_cache';

  Future<AgingSummary> summary({
    String? customer,
    bool useCacheOnFailure = true,
  }) async {
    final company = VanSalePrefs.instance.company.trim();
    try {
      final env = await session.store.callMethod(
        VanSaleApiMethods.agingSummary,
        args: {
          if (customer != null && customer.isNotEmpty) 'customer': customer,
          if (company.isNotEmpty) 'company': company,
        },
      );
      final data = env.data;
      if (data is! Map) throw StateError('Unexpected aging payload');
      final summary = AgingSummary.fromJson(Map<String, dynamic>.from(data));
      if (customer == null || customer.isEmpty) {
        await _saveCache(summary);
      }
      return summary;
    } catch (_) {
      if (!useCacheOnFailure || (customer != null && customer.isNotEmpty)) {
        rethrow;
      }
      final cached = await loadCachedSummary();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> detail({
    String? customer,
    int page = 1,
    int pageSize = 50,
  }) async {
    final company = VanSalePrefs.instance.company.trim();
    final env = await session.store.callMethod(
      VanSaleApiMethods.agingDetail,
      args: {
        'page': page,
        'page_size': pageSize,
        if (customer != null && customer.isNotEmpty) 'customer': customer,
        if (company.isNotEmpty) 'company': company,
      },
    );
    final data = env.data;
    if (data is Map && data['items'] is List) {
      return [
        for (final raw in data['items'] as List)
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];
    }
    if (data is List) {
      return [
        for (final raw in data)
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];
    }
    return const [];
  }

  Future<AgingSummary?> loadCachedSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      return AgingSummary.fromJson(
        Map<String, dynamic>.from(map),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(AgingSummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(summary.toJson()));
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device work mode for VanSale (persisted).
enum VanSaleWorkMode {
  /// Require login + site reachability before local mutations; sync when connected.
  online,

  /// Local SQLite only; sync flush disabled.
  offline,

  /// Local writes always; sync opportunistically when connected (legacy hybrid).
  onlineOffline,
}

/// Persisted VanSale connection / ERP defaults and device policy.
class VanSalePrefs {
  VanSalePrefs._();
  static final VanSalePrefs instance = VanSalePrefs._();

  static const _kSiteUrl = 'van_sale.site_url';
  static const _kWarehouse = 'van_sale.warehouse';
  static const _kCompany = 'van_sale.company';
  static const _kWorkMode = 'van_sale.work_mode';
  static const _kAllowNegativeStock = 'van_sale.allow_negative_stock';
  static const _kBackgroundSync = 'van_sale.background_sync';
  static const _kAutoSyncAfterWrite = 'van_sale.auto_sync_after_write';
  static const _kLowStockThreshold = 'van_sale.low_stock_threshold';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Tests only — rebind SharedPreferences after setMockInitialValues.
  @visibleForTesting
  Future<void> resetForTest() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get prefs {
    final p = _prefs;
    if (p == null) {
      throw StateError('VanSalePrefs.init() required');
    }
    return p;
  }

  String get siteUrl =>
      prefs.getString(_kSiteUrl) ?? 'https://demo.zatgo.online';

  Future<void> setSiteUrl(String value) async {
    await prefs.setString(_kSiteUrl, value.replaceAll(RegExp(r'/$'), ''));
  }

  String get warehouse => prefs.getString(_kWarehouse) ?? '';

  Future<void> setWarehouse(String value) async {
    await prefs.setString(_kWarehouse, value.trim());
  }

  String get company => prefs.getString(_kCompany) ?? '';

  Future<void> setCompany(String value) async {
    await prefs.setString(_kCompany, value.trim());
  }

  /// Default: [VanSaleWorkMode.online].
  VanSaleWorkMode get workMode {
    final raw = prefs.getString(_kWorkMode);
    return switch (raw) {
      'offline' => VanSaleWorkMode.offline,
      'online_offline' || 'onlineOffline' => VanSaleWorkMode.onlineOffline,
      _ => VanSaleWorkMode.online,
    };
  }

  Future<void> setWorkMode(VanSaleWorkMode mode) async {
    final value = switch (mode) {
      VanSaleWorkMode.online => 'online',
      VanSaleWorkMode.offline => 'offline',
      VanSaleWorkMode.onlineOffline => 'online_offline',
    };
    await prefs.setString(_kWorkMode, value);
  }

  bool get allowNegativeStock =>
      prefs.getBool(_kAllowNegativeStock) ?? false;

  Future<void> setAllowNegativeStock(bool value) async {
    await prefs.setBool(_kAllowNegativeStock, value);
  }

  bool get backgroundSync => prefs.getBool(_kBackgroundSync) ?? true;

  Future<void> setBackgroundSync(bool value) async {
    await prefs.setBool(_kBackgroundSync, value);
  }

  bool get autoSyncAfterWrite =>
      prefs.getBool(_kAutoSyncAfterWrite) ?? false;

  Future<void> setAutoSyncAfterWrite(bool value) async {
    await prefs.setBool(_kAutoSyncAfterWrite, value);
  }

  double get lowStockThreshold =>
      prefs.getDouble(_kLowStockThreshold) ?? 5;

  Future<void> setLowStockThreshold(double value) async {
    final v = value.isFinite && value >= 0 ? value : 5.0;
    await prefs.setDouble(_kLowStockThreshold, v);
  }
}

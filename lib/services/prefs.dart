import 'package:shared_preferences/shared_preferences.dart';

/// Persisted VanSale connection / ERP defaults.
class VanSalePrefs {
  VanSalePrefs._();
  static final VanSalePrefs instance = VanSalePrefs._();

  static const _kSiteUrl = 'van_sale.site_url';
  static const _kWarehouse = 'van_sale.warehouse';
  static const _kCompany = 'van_sale.company';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
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
}

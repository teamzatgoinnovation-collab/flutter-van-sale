import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import 'prefs.dart';
import 'van_sale_api_methods.dart';
import 'van_sale_context.dart';

/// Password-session state for VanSale (user + admin).
class VanSaleSession extends ChangeNotifier {
  VanSaleSession() {
    final base = const String.fromEnvironment(
      'FRAPPE_BASE_URL',
      defaultValue: 'https://demo.zatgo.online',
    );
    baseUrl = base.replaceAll(RegExp(r'/$'), '');
  }

  final ErpnextSessionStore store = ErpnextSessionStore();

  String baseUrl = 'https://demo.zatgo.online';
  String? user;
  String? fullName;
  String? lastError;
  VanSaleContext? context;
  /// When admin also has user role: false = All vans, true = My van.
  bool preferUserMode = false;

  bool get connected => store.connected;
  bool get isAdmin => context?.isAdmin == true;
  bool get isFieldUser => context?.isUser == true;
  bool get hasVansaleAccess => context?.hasVansaleAccess == true;
  bool get showAdminShell =>
      isAdmin && !(preferUserMode && isFieldUser);

  void updateBaseUrl(String value) {
    baseUrl = value.replaceAll(RegExp(r'/$'), '');
    notifyListeners();
  }

  void restorePreferUserModeFromPrefs() {
    try {
      preferUserMode = VanSalePrefs.instance.preferUserMode;
    } catch (_) {
      // Prefs may be uninitialized in unit tests.
    }
  }

  Future<ErpnextLoginResult> login({
    required String usr,
    required String pwd,
  }) async {
    final result = await store.login(baseUrl: baseUrl, usr: usr, pwd: pwd);
    if (result is ErpnextLoginOk) {
      user = result.session.user;
      fullName = result.session.fullName;
      baseUrl = result.session.baseUrl;
      lastError = null;
      try {
        await loadContext();
      } catch (e) {
        lastError = 'Could not load VanSale roles: $e';
      }
      restorePreferUserModeFromPrefs();
    } else if (result is ErpnextLoginFail) {
      user = null;
      fullName = null;
      context = null;
      lastError = result.message;
    }
    notifyListeners();
    return result;
  }

  Future<void> loadContext() async {
    if (!connected) {
      context = null;
      return;
    }
    final env = await store.callMethod(VanSaleApiMethods.meContext);
    final data = env.data;
    if (data is Map) {
      context = VanSaleContext.fromJson(Map<String, dynamic>.from(data));
      user = context!.user;
      fullName = context!.fullName;
    } else {
      context = null;
    }
    restorePreferUserModeFromPrefs();
    notifyListeners();
  }

  void setPreferUserMode(bool value) {
    preferUserMode = value;
    try {
      VanSalePrefs.instance.prefs; // ensure init'd before async write
      unawaited(VanSalePrefs.instance.setPreferUserMode(value));
    } catch (_) {
      // Prefs may be uninitialized in unit tests.
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await store.logout();
    user = null;
    fullName = null;
    lastError = null;
    context = null;
    preferUserMode = false;
    notifyListeners();
  }

  Future<ErpnextPingResult> ping() => erpnextPing(baseUrl);
}

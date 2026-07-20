import 'package:flutter/foundation.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

/// ERPNext password-session state for Go Van.
class GoVanSession extends ChangeNotifier {
  GoVanSession() {
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
  bool allowMockWithoutLogin = false;

  bool get connected => store.connected;

  void updateBaseUrl(String value) {
    baseUrl = value.replaceAll(RegExp(r'/$'), '');
    notifyListeners();
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
      allowMockWithoutLogin = false;
    } else if (result is ErpnextLoginFail) {
      user = null;
      fullName = null;
      lastError = result.message;
    }
    notifyListeners();
    return result;
  }

  Future<void> logout() async {
    await store.logout();
    user = null;
    fullName = null;
    lastError = null;
    allowMockWithoutLogin = false;
    notifyListeners();
  }

  void continueOffline() {
    allowMockWithoutLogin = true;
    lastError = null;
    notifyListeners();
  }

  Future<ErpnextPingResult> ping() => erpnextPing(baseUrl);
}

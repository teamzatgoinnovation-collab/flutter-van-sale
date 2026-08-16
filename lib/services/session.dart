import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import 'prefs.dart';
import 'van_sale_context.dart';
import 'van_sale_policy.dart';

/// Fixed ERPNext server for this app build. Overridable only via
/// --dart-define for internal dev/testing builds (e.g. pointing at a local
/// bench) — not user-editable in the app itself.
const String kErpBaseUrl = 'https://vansale.zatgo.online';

const _kSecureStoreBaseUrl = 'vansale_session_base_url';
const _kSecureStoreSidCookie = 'vansale_session_sid_cookie';
const _kSecureStoreHostHeader = 'vansale_session_host_header';
const _kSecureStoreUser = 'vansale_session_user';
const _kSecureStoreFullName = 'vansale_session_full_name';

/// Password-session state for VanSale (user + admin).
class VanSaleSession extends ChangeNotifier {
  VanSaleSession({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    final base = const String.fromEnvironment(
      'FRAPPE_BASE_URL',
      defaultValue: kErpBaseUrl,
    );
    baseUrl = base.replaceAll(RegExp(r'/$'), '');
  }

  final ErpnextSessionStore store = ErpnextSessionStore();
  final FlutterSecureStorage _secureStorage;

  String baseUrl = kErpBaseUrl;
  String? user;
  String? fullName;
  String? lastError;
  VanSaleContext? context;
  /// When admin also has user role: false = All vans, true = My van.
  bool preferUserMode = false;

  /// True for one boot cycle after [restoreSessionFromStorage] repopulates
  /// the session from a persisted (not freshly-typed) login — lets the
  /// caller be lenient about a context/access check that can't be verified
  /// while offline, instead of forcing a logout. Cleared once consumed.
  bool restoredFromStorage = false;

  bool get connected => store.connected;
  bool get isAdmin => context?.isAdmin == true;
  bool get isFieldUser => context?.isUser == true;
  bool get hasVansaleAccess => context?.hasVansaleAccess == true;
  bool get showAdminShell =>
      isAdmin && !(preferUserMode && isFieldUser);

  /// Set by the hub lookup right before login — not a user-editable
  /// setting, just how the resolved per-account site gets applied.
  void applyResolvedBaseUrl(String value) {
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
    final result = await store.login(
      baseUrl: baseUrl,
      usr: usr,
      pwd: pwd,
      hostHeader: const String.fromEnvironment('FRAPPE_HOST_HEADER').isEmpty
          ? null
          : const String.fromEnvironment('FRAPPE_HOST_HEADER'),
    );
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

  /// Persists the current session (site URL + session cookie + identity)
  /// to encrypted local storage so [restoreSessionFromStorage] can bring
  /// the app back into an authenticated state after a restart with no
  /// network available. Call only once access has been positively
  /// confirmed (see main.dart's post-login access check) — never persist
  /// a session that hasn't been verified to actually have VanSale access.
  Future<void> persistSession() async {
    final sid = store.sidCookie;
    final base = store.baseUrl;
    if (sid == null || base == null) return;
    try {
      await Future.wait([
        _secureStorage.write(key: _kSecureStoreBaseUrl, value: base),
        _secureStorage.write(key: _kSecureStoreSidCookie, value: sid),
        if (store.hostHeader != null)
          _secureStorage.write(key: _kSecureStoreHostHeader, value: store.hostHeader)
        else
          _secureStorage.delete(key: _kSecureStoreHostHeader),
        _secureStorage.write(key: _kSecureStoreUser, value: user ?? ''),
        _secureStorage.write(key: _kSecureStoreFullName, value: fullName ?? ''),
      ]);
    } catch (_) {
      // Secure storage unavailable — the current session still works, it
      // just won't survive an app restart while offline this time.
    }
  }

  Future<void> _clearPersistedSession() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: _kSecureStoreBaseUrl),
        _secureStorage.delete(key: _kSecureStoreSidCookie),
        _secureStorage.delete(key: _kSecureStoreHostHeader),
        _secureStorage.delete(key: _kSecureStoreUser),
        _secureStorage.delete(key: _kSecureStoreFullName),
      ]);
    } catch (_) {
      // Best-effort — nothing sensitive is left usable without the sid
      // cookie value anyway, and store.logout() already invalidated it.
    }
  }

  /// Re-establishes an authenticated session from encrypted storage without
  /// any network call, so the app opens straight into the shell (with
  /// cached local data + the durable sync queue) even when offline. Returns
  /// true if a session was restored. The first API call afterward may still
  /// fail if the server-side session has since expired — callers should
  /// treat that as "stay in the app, offline" rather than an immediate
  /// forced logout, and only actually clear the session on an explicit
  /// sign-out or a confirmed (online) "no access" response.
  Future<bool> restoreSessionFromStorage() async {
    try {
      final base = await _secureStorage.read(key: _kSecureStoreBaseUrl);
      final sid = await _secureStorage.read(key: _kSecureStoreSidCookie);
      if (base == null || base.isEmpty || sid == null || sid.isEmpty) {
        return false;
      }
      final hostHeader = await _secureStorage.read(key: _kSecureStoreHostHeader);
      store.restoreSession(baseUrl: base, sidCookie: sid, hostHeader: hostHeader);
      baseUrl = base;
      final storedUser = await _secureStorage.read(key: _kSecureStoreUser);
      final storedFullName = await _secureStorage.read(key: _kSecureStoreFullName);
      user = (storedUser == null || storedUser.isEmpty) ? null : storedUser;
      fullName = (storedFullName == null || storedFullName.isEmpty) ? null : storedFullName;
      restoredFromStorage = true;
      notifyListeners();
      return true;
    } catch (_) {
      // Secure storage unavailable (e.g. some test/desktop environments) —
      // fall back to requiring an interactive login, same as before.
      return false;
    }
  }

  Future<void> loadContext() async {
    if (!connected) {
      context = null;
      return;
    }
    final env = await store.callMethod(ZatGoApiMethods.goVanMeContext);
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
    await _clearPersistedSession();
    user = null;
    fullName = null;
    lastError = null;
    context = null;
    preferUserMode = false;
    restoredFromStorage = false;
    VanSalePolicy.instance.invalidateOnlineReachability();
    notifyListeners();
  }

  Future<ErpnextPingResult> ping() => erpnextPing(baseUrl);
}

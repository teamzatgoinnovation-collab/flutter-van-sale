import 'connection.dart';
import 'prefs.dart';
import 'session.dart';

/// Device policy facade for stock / work-mode / sync decisions.
class VanSalePolicy {
  VanSalePolicy._();
  static final VanSalePolicy instance = VanSalePolicy._();

  VanSalePrefs get _prefs => VanSalePrefs.instance;

  VanSaleWorkMode get workMode => _prefs.workMode;

  bool get allowNegativeStock => _prefs.allowNegativeStock;

  double get lowStockThreshold => _prefs.lowStockThreshold;

  /// Sync flush / background allowed (not Offline mode).
  bool get syncAllowed => workMode != VanSaleWorkMode.offline;

  /// After local write: Online always attempts flush; Hybrid only if toggle on.
  bool get shouldAttemptFlushAfterWrite {
    if (!syncAllowed) return false;
    if (workMode == VanSaleWorkMode.online) return true;
    return _prefs.autoSyncAfterWrite;
  }

  bool get backgroundSyncDesired =>
      syncAllowed && _prefs.backgroundSync;

  /// Gate mutations when work mode is Online.
  Future<void> assertCanMutate(VanSaleSession? session) async {
    if (workMode != VanSaleWorkMode.online) return;
    if (session == null || !session.connected) {
      throw StateError(
        'Online mode requires sign-in. Switch to Offline or Online+Offline '
        'in Settings, or sign in.',
      );
    }
    final ping = await testConnection(session);
    if (!ping.ok) {
      throw StateError(
        'Online mode: site unreachable (${ping.message}). '
        'Check connection or switch work mode in Settings.',
      );
    }
  }
}

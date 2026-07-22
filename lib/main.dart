import 'dart:async';

import 'package:flutter/material.dart';

import 'data/van_sale_db.dart';
import 'data/van_sale_repo.dart';
import 'core/di/van_sale_services.dart';
import 'pages/login_page.dart';
import 'pages/shell.dart';
import 'services/prefs.dart';
import 'services/session.dart';
import 'services/sync_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initVanSaleSqflite();
  await VanSalePrefs.instance.init();
  await vanSaleRepo.init();
  await VanSaleServices.bootstrap();
  final session = VanSaleSession();
  session.updateBaseUrl(VanSalePrefs.instance.siteUrl);
  runApp(VanSaleApp(session: session));
}

class VanSaleApp extends StatefulWidget {
  const VanSaleApp({super.key, required this.session});

  final VanSaleSession session;

  @override
  State<VanSaleApp> createState() => _VanSaleAppState();
}

class _VanSaleAppState extends State<VanSaleApp> with WidgetsBindingObserver {
  bool _showLogin = true;
  late final SyncService _sync;

  bool get _authed => widget.session.connected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync = SyncService(
      widget.session,
      db: VanSaleServices.instance.db,
      repo: VanSaleServices.instance.repo,
      customers: VanSaleServices.instance.customers,
      products: VanSaleServices.instance.products,
    );
    _syncGate();
    widget.session.addListener(_syncGate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_syncGate);
    _sync.stopBackgroundSync();
    _sync.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _authed) {
      unawaited(() async {
        try {
          await _sync.flush(mode: SyncMode.background);
        } catch (_) {}
      }());
    }
  }

  void _syncGate() {
    final authed = _authed;
    if (_showLogin == !authed) {
      if (authed) {
        _afterAuth();
      }
      return;
    }
    setState(() => _showLogin = !authed);
    if (authed) {
      _afterAuth();
    } else {
      _sync.stopBackgroundSync();
    }
  }

  Future<void> _afterAuth() async {
    _sync.startBackgroundSync();
    try {
      await _sync.flush(mode: SyncMode.manual);
    } catch (e) {
      debugPrint('VanSale sync after auth: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VanSale',
      debugShowCheckedModeBanner: false,
      theme: buildVanSaleTheme(brightness: Brightness.light),
      darkTheme: buildVanSaleTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: _showLogin
          ? LoginPage(
              session: widget.session,
              onAuthed: () {
                setState(() => _showLogin = false);
                _afterAuth();
              },
            )
          : VanSaleShell(
              session: widget.session,
              sync: _sync,
              onRequireLogin: () => setState(() => _showLogin = true),
            ),
    );
  }
}

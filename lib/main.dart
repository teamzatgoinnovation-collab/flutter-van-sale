import 'dart:async';

import 'package:flutter/material.dart';

import 'data/van_sale_db.dart';
import 'data/van_sale_repo.dart';
import 'core/di/van_sale_services.dart';
import 'pages/admin_shell.dart';
import 'pages/login_page.dart';
import 'pages/shell.dart';
import 'product/models/product_model.dart';
import 'services/prefs.dart';
import 'services/session.dart';
import 'services/sync_service.dart';
import 'services/van_sale_policy.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Paint a splash immediately; heavy SQLite / prefs / fonts run after first frame.
  runApp(const _VanSaleBootstrap());
}

class _VanSaleBootstrap extends StatefulWidget {
  const _VanSaleBootstrap();

  @override
  State<_VanSaleBootstrap> createState() => _VanSaleBootstrapState();
}

class _VanSaleBootstrapState extends State<_VanSaleBootstrap> {
  Object? _error;
  VanSaleSession? _session;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      await initVanSaleSqflite();
      await VanSalePrefs.instance.init();
      ProductModel.setDefaultLowStockThreshold(
        VanSalePrefs.instance.lowStockThreshold,
      );
      // Fonts + DB in parallel after prefs (prefs is tiny / needed first).
      await Future.wait([
        preloadVanSaleFonts(),
        vanSaleRepo.init(),
        VanSaleServices.bootstrap(),
      ]);
      final session = VanSaleSession();
      session.updateBaseUrl(VanSalePrefs.instance.siteUrl);
      if (!mounted) return;
      setState(() => _session = session);
    } catch (e, st) {
      debugPrint('VanSale bootstrap failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return VanSaleApp(session: session);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Plain Material theme — avoid GoogleFonts until preload finishes.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F4C5C)),
      ),
      home: Scaffold(
        body: Center(
          child: _error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Starting VanSale…'),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Startup failed: $_error', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() => _error = null);
                          unawaited(_boot());
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class VanSaleApp extends StatefulWidget {
  const VanSaleApp({super.key, required this.session});

  final VanSaleSession session;

  @override
  State<VanSaleApp> createState() => _VanSaleAppState();
}

class _VanSaleAppState extends State<VanSaleApp> with WidgetsBindingObserver {
  bool _showLogin = true;
  String? _accessBlock;
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
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onSessionChanged);
    _sync.stopBackgroundSync();
    _sync.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _authed &&
        VanSalePolicy.instance.backgroundSyncDesired) {
      unawaited(() async {
        try {
          await _sync.flush(mode: SyncMode.background);
        } catch (_) {}
      }());
    }
  }

  void _onSessionChanged() {
    _syncGate();
    if (mounted) setState(() {});
  }

  void _syncGate() {
    final authed = _authed;
    if (_showLogin == !authed) {
      // Already showing the correct root — ignore session noise.
      // Keep any accessBlock banner on the login screen.
      if (!authed) return;
      setState(() {});
      return;
    }
    setState(() {
      _showLogin = !authed;
      if (authed) _accessBlock = null;
    });
    if (authed) {
      _afterAuth();
    } else {
      _sync.stopBackgroundSync();
    }
  }

  Future<void> _applyProfileWarehouse() async {
    final wh = widget.session.context?.profile?.warehouse.trim() ?? '';
    if (wh.isNotEmpty && VanSalePrefs.instance.warehouse.trim().isEmpty) {
      await VanSalePrefs.instance.setWarehouse(wh);
    }
  }

  Future<void> _afterAuth() async {
    try {
      if (widget.session.context == null) {
        await widget.session.loadContext();
      }
    } catch (e) {
      debugPrint('VanSale context after auth: $e');
    }
    if (!widget.session.hasVansaleAccess) {
      final msg =
          widget.session.lastError ??
          'No VanSale User or VanSale Admin role on this account.';
      await widget.session.logout();
      if (!mounted) return;
      setState(() {
        _showLogin = true;
        _accessBlock = msg;
      });
      return;
    }
    await _applyProfileWarehouse();
    _sync.applyPrefs();
    if (VanSalePolicy.instance.backgroundSyncDesired) {
      _sync.startBackgroundSync();
    } else {
      _sync.stopBackgroundSync();
    }
    try {
      await _sync.flush(mode: SyncMode.manual);
    } catch (e) {
      debugPrint('VanSale sync after auth: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = _showLogin
        ? LoginPage(
            session: widget.session,
            accessMessage: _accessBlock,
            onAuthed: () {
              // Session already notified; _syncGate flips to shell and runs _afterAuth once.
              setState(() => _accessBlock = null);
            },
          )
        : widget.session.showAdminShell
        ? AdminShell(
            session: widget.session,
            sync: _sync,
            onRequireLogin: () => setState(() => _showLogin = true),
          )
        : VanSaleShell(
            session: widget.session,
            sync: _sync,
            onRequireLogin: () => setState(() => _showLogin = true),
          );

    return MaterialApp(
      title: 'VanSale',
      debugShowCheckedModeBanner: false,
      theme: vanSaleLightTheme(),
      darkTheme: vanSaleDarkTheme(),
      themeMode: ThemeMode.system,
      home: home,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'data/van_sale_db.dart';
import 'data/van_sale_repo.dart';
import 'core/di/van_sale_services.dart';
import 'pages/admin_shell.dart';
import 'pages/login_page.dart';
import 'pages/shell.dart';
import 'pages/sync_setup_page.dart';
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
      // Offline-days support: if a prior login was persisted to secure
      // storage, restore it now (no network call) so the app opens
      // straight into the shell with cached local data + the sync queue
      // instead of forcing the driver back through /login while offline.
      await session.restoreSessionFromStorage();
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B2B2B)),
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
  bool _settingUp = false;
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
      if (authed) {
        _accessBlock = null;
        _settingUp = true;
      }
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
    final vehicle = widget.session.context?.profile?.vehicle?.trim() ?? '';
    if (vehicle.isNotEmpty && VanSalePrefs.instance.vehicle.trim().isEmpty) {
      await VanSalePrefs.instance.setVehicle(vehicle);
    }
  }

  Future<void> _afterAuth() async {
    var contextLoadFailed = false;
    try {
      if (widget.session.context == null) {
        await widget.session.loadContext();
      }
    } catch (e) {
      debugPrint('VanSale context after auth: $e');
      contextLoadFailed = true;
    }
    final restoredOffline = widget.session.restoredFromStorage && contextLoadFailed;
    widget.session.restoredFromStorage = false;
    if (!widget.session.hasVansaleAccess) {
      if (restoredOffline) {
        // A previously-verified session was restored from secure storage,
        // but we can't reach the server right now to re-confirm access.
        // Trust the prior verification and continue offline with cached
        // local data — access will be re-checked automatically next time
        // loadContext() succeeds. Only an explicit sign-out, or a server
        // response that actually says "no access", should log this out.
      } else {
        final msg =
            widget.session.lastError ??
            'No VanSale User or VanSale Admin role on this account.';
        await widget.session.logout();
        if (!mounted) return;
        setState(() {
          _showLogin = true;
          _settingUp = false;
          _accessBlock = msg;
        });
        return;
      }
    } else {
      await widget.session.persistSession();
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
    if (!mounted) return;
    setState(() => _settingUp = false);
    final needsSetup = VanSalePrefs.instance.warehouse.trim().isEmpty ||
        VanSalePrefs.instance.vehicle.trim().isEmpty;
    if (needsSetup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showVanSetupModal();
      });
    }
  }

  Future<void> _showVanSetupModal() async {
    final whCtrl = TextEditingController(text: VanSalePrefs.instance.warehouse);
    final vehCtrl = TextEditingController(text: VanSalePrefs.instance.vehicle);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            final canContinue = whCtrl.text.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('Set up your van'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Confirm the warehouse and vehicle for this device '
                    'before you start selling.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: whCtrl,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Van warehouse',
                      prefixIcon: Icon(Icons.warehouse_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: vehCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle (optional)',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: !canContinue
                      ? null
                      : () async {
                          await VanSalePrefs.instance.setWarehouse(
                            whCtrl.text.trim(),
                          );
                          await VanSalePrefs.instance.setVehicle(
                            vehCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        ),
      ),
    );
    whCtrl.dispose();
    vehCtrl.dispose();
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
        : _settingUp
        ? SyncSetupPage(sync: _sync)
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

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: VanSalePrefs.instance.themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'ZatGo VanSale',
        debugShowCheckedModeBanner: false,
        theme: vanSaleLightTheme(),
        darkTheme: vanSaleDarkTheme(),
        themeMode: mode,
        home: home,
      ),
    );
  }
}

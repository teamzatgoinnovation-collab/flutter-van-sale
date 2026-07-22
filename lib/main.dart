import 'package:flutter/material.dart';

import 'data/van_sale_db.dart';
import 'data/van_sale_repo.dart';
import 'pages/login_page.dart';
import 'pages/shell.dart';
import 'services/session.dart';
import 'services/sync_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initVanSaleSqflite();
  await vanSaleRepo.init();
  runApp(VanSaleApp(session: VanSaleSession()));
}

class VanSaleApp extends StatefulWidget {
  const VanSaleApp({super.key, required this.session});

  final VanSaleSession session;

  @override
  State<VanSaleApp> createState() => _VanSaleAppState();
}

class _VanSaleAppState extends State<VanSaleApp> {
  bool _showLogin = true;
  late final SyncService _sync;

  bool get _authed =>
      widget.session.connected || widget.session.allowMockWithoutLogin;

  @override
  void initState() {
    super.initState();
    _sync = SyncService(widget.session);
    _syncGate();
    widget.session.addListener(_syncGate);
  }

  @override
  void dispose() {
    widget.session.removeListener(_syncGate);
    super.dispose();
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
    }
  }

  Future<void> _afterAuth() async {
    try {
      await _sync.flush();
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

import 'package:flutter/material.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import '../services/prefs.dart';
import '../services/session.dart';
import 'site_url_settings_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session, required this.onAuthed});

  final VanSaleSession session;
  final VoidCallback onAuthed;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _usr = TextEditingController();
  final _pwd = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    widget.session.updateBaseUrl(VanSalePrefs.instance.siteUrl);
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
    _enter.forward();
  }

  @override
  void dispose() {
    _usr.dispose();
    _pwd.dispose();
    _enter.dispose();
    super.dispose();
  }

  Future<void> _openSiteUrlSettings() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SiteUrlSettingsPage(session: widget.session),
      ),
    );
    if (!mounted) return;
    // Reflect any URL change in the session for the next sign-in.
    widget.session.updateBaseUrl(VanSalePrefs.instance.siteUrl);
    setState(() {});
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    final url = VanSalePrefs.instance.siteUrl.trim();
    widget.session.updateBaseUrl(url);
    final result = await widget.session.login(
      usr: _usr.text.trim(),
      pwd: _pwd.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is ErpnextLoginOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signed in as ${result.session.fullName}')),
      );
      widget.onAuthed();
    } else if (result is ErpnextLoginFail) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final siteUrl = VanSalePrefs.instance.siteUrl;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0F172A),
                    scheme.primary.withValues(alpha: 0.22),
                    const Color(0xFF0F172A),
                  ]
                : [
                    const Color(0xFFF0FDFA),
                    scheme.primary.withValues(alpha: 0.12),
                    const Color(0xFFF8FAFC),
                  ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Site URL',
                  onPressed: _busy ? null : _openSiteUrlSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ),
              Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 24),
                          Center(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                Icons.local_shipping_outlined,
                                size: 32,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'ZatGo',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'VanSale',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sign in with your account to load routes, stock, and sales.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: _busy ? null : _openSiteUrlSettings,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                siteUrl,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(
                                alpha: isDark ? 0.92 : 0.95,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: _usr,
                                    decoration: const InputDecoration(
                                      labelText: 'Email / User',
                                      prefixIcon: Icon(Icons.person_outline),
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                    autocorrect: false,
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _pwd,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        tooltip: _obscure ? 'Show' : 'Hide',
                                        onPressed: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                        icon: Icon(
                                          _obscure
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                      ),
                                    ),
                                    obscureText: _obscure,
                                    onSubmitted: (_) =>
                                        _busy ? null : _login(),
                                  ),
                                  if (widget.session.lastError != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      widget.session.lastError!,
                                      style: TextStyle(color: scheme.error),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  FilledButton(
                                    onPressed: _busy ? null : _login,
                                    child: _busy
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: scheme.onPrimary,
                                            ),
                                          )
                                        : const Text('Sign in'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/connection.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import '../widgets/widgets.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.session,
    required this.sync,
    this.onSignOut,
  });

  final VanSaleSession session;
  final SyncService sync;
  final VoidCallback? onSignOut;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  bool _busy = false;

  Future<void> _ping() async {
    setState(() => _busy = true);
    final result = await testConnection(widget.session);
    if (!mounted) return;
    if (result.ok) {
      await widget.sync.flush();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    setState(() => _busy = false);
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    await widget.session.logout();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onSignOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PageScaffold(
      title: 'Connection',
      subtitle: 'ERPNext session · SQLite stays local',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Sign in with site email and password. Sales stay on device until '
            'ERP acknowledges each client_id.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardTheme.color ?? scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Session',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (session.connected)
                      Text(
                        'Signed in as ${session.fullName ?? session.user}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (session.allowMockWithoutLogin)
                      Text(
                        'Offline mode — SQLite route data.',
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Text(
                        'Not signed in.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _busy ? null : _logout,
                          child: const Text('Sign out'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _busy ? null : _ping,
                          child: const Text('Test site'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      session.connected
                          ? 'Status: Connected as ${session.user}'
                          : session.allowMockWithoutLogin
                              ? 'Status: Offline'
                              : 'Status: Not signed in'
                                  '${session.lastError != null ? ' — ${session.lastError}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/prefs.dart';
import '../services/session.dart';

/// Login-time site URL editor — connection URL only.
class SiteUrlSettingsPage extends StatefulWidget {
  const SiteUrlSettingsPage({super.key, required this.session});

  final VanSaleSession session;

  @override
  State<SiteUrlSettingsPage> createState() => _SiteUrlSettingsPageState();
}

class _SiteUrlSettingsPageState extends State<SiteUrlSettingsPage> {
  late final TextEditingController _url;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: VanSalePrefs.instance.siteUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = _url.text.trim().replaceAll(RegExp(r'/$'), '');
    if (next.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a site URL')),
      );
      return;
    }
    setState(() => _busy = true);
    await VanSalePrefs.instance.setSiteUrl(next);
    widget.session.updateBaseUrl(next);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Site URL saved · $next')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Site URL'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Set the server address used for sign-in and sync.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Site URL',
              hintText: 'https://…',
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _save(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

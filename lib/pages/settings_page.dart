import 'package:flutter/material.dart';

import '../services/connection.dart';
import '../services/prefs.dart';
import '../services/session.dart';
import '../services/sync_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.session,
    required this.sync,
  });

  final VanSaleSession session;
  final SyncService sync;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url;
  late final TextEditingController _warehouse;
  late final TextEditingController _company;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final prefs = VanSalePrefs.instance;
    _url = TextEditingController(text: prefs.siteUrl);
    _warehouse = TextEditingController(text: prefs.warehouse);
    _company = TextEditingController(text: prefs.company);
  }

  @override
  void dispose() {
    _url.dispose();
    _warehouse.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final prefs = VanSalePrefs.instance;
    await prefs.setSiteUrl(_url.text.trim());
    await prefs.setWarehouse(_warehouse.text.trim());
    await prefs.setCompany(_company.text.trim());
    widget.session.updateBaseUrl(prefs.siteUrl);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _ping() async {
    setState(() => _busy = true);
    widget.session.updateBaseUrl(_url.text.trim());
    final result = await testConnection(widget.session);
    if (!mounted) return;
    if (result.ok && widget.session.connected) {
      await widget.sync.flush();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'ERPNext connection and van defaults. Sales sync to Sales Invoice / '
            'Payment Entry / Stock Entry.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Site URL',
              hintText: 'https://erp.zatgo.online',
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _warehouse,
            decoration: const InputDecoration(
              labelText: 'Van warehouse',
              hintText: 'ERPNext Warehouse name',
              prefixIcon: Icon(Icons.warehouse_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _company,
            decoration: const InputDecoration(
              labelText: 'Company (optional)',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _ping,
            child: const Text('Test site'),
          ),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              return Card(
                child: ListTile(
                  title: Text(
                    session.connected
                        ? 'Signed in as ${session.fullName ?? session.user}'
                        : 'Not signed in',
                  ),
                  subtitle: Text(session.baseUrl),
                ),
              );
            },
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

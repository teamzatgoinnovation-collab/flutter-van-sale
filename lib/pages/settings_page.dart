import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../product/models/product_model.dart';
import '../services/connection.dart';
import '../services/prefs.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import '../services/van_sale_policy.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.session, required this.sync});

  final VanSaleSession session;
  final SyncService sync;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url;
  late final TextEditingController _warehouse;
  late final TextEditingController _company;
  late final TextEditingController _lowStock;
  late VanSaleWorkMode _workMode;
  late bool _allowNegativeStock;
  late bool _backgroundSync;
  late bool _autoSyncAfterWrite;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final prefs = VanSalePrefs.instance;
    _url = TextEditingController(text: prefs.siteUrl);
    _warehouse = TextEditingController(text: prefs.warehouse);
    _company = TextEditingController(text: prefs.company);
    _lowStock = TextEditingController(
      text: prefs.lowStockThreshold.toStringAsFixed(
        prefs.lowStockThreshold == prefs.lowStockThreshold.roundToDouble()
            ? 0
            : 1,
      ),
    );
    _workMode = prefs.workMode;
    _allowNegativeStock = prefs.allowNegativeStock;
    _backgroundSync = prefs.backgroundSync;
    _autoSyncAfterWrite = prefs.autoSyncAfterWrite;
  }

  @override
  void dispose() {
    _url.dispose();
    _warehouse.dispose();
    _company.dispose();
    _lowStock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final prefs = VanSalePrefs.instance;
    final previousUrl = prefs.siteUrl;
    final nextUrl = _url.text.trim().replaceAll(RegExp(r'/$'), '');
    final siteChanged = nextUrl.isNotEmpty && nextUrl != previousUrl;

    await prefs.setSiteUrl(nextUrl.isEmpty ? previousUrl : nextUrl);
    await prefs.setWarehouse(_warehouse.text.trim());
    await prefs.setCompany(_company.text.trim());
    await prefs.setWorkMode(_workMode);
    await prefs.setAllowNegativeStock(_allowNegativeStock);
    await prefs.setBackgroundSync(_backgroundSync);
    await prefs.setAutoSyncAfterWrite(_autoSyncAfterWrite);
    final threshold = double.tryParse(_lowStock.text.trim()) ?? 5;
    await prefs.setLowStockThreshold(threshold);
    ProductModel.setDefaultLowStockThreshold(prefs.lowStockThreshold);

    widget.session.updateBaseUrl(prefs.siteUrl);
    widget.sync.applyPrefs();

    if (siteChanged) {
      widget.sync.stopBackgroundSync();
      final messenger = ScaffoldMessenger.of(context);
      await widget.session.logout();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Site updated to ${prefs.siteUrl}. Sign in again for the new site.',
          ),
        ),
      );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }

    if (VanSalePolicy.instance.backgroundSyncDesired &&
        widget.session.connected) {
      widget.sync.startBackgroundSync();
    } else {
      widget.sync.stopBackgroundSync();
    }

    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _ping() async {
    setState(() => _busy = true);
    widget.session.updateBaseUrl(_url.text.trim());
    final result = await testConnection(widget.session);
    if (!mounted) return;
    if (result.ok &&
        widget.session.connected &&
        VanSalePolicy.instance.syncAllowed) {
      await widget.sync.flush();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'ERPNext connection, van defaults, and device policy. Sales sync to '
            'Sales Invoice / Payment Entry / Stock Entry.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          _sectionTitle(context, 'Connection'),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Site URL',
              hintText: 'https://erp.zatgo.online',
              prefixIcon: Icon(Icons.link),
              helperText:
                  'Changing the site signs you out so you can log in fresh',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _ping,
            child: const Text('Test site'),
          ),
          const SizedBox(height: 8),
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
          _sectionTitle(context, 'Van defaults'),
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
          _sectionTitle(context, 'Work mode'),
          Text(
            'Online (default): sell only when signed in and site reachable. '
            'Offline: local only, sync off. Online+Offline: local writes, '
            'sync when connected.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<VanSaleWorkMode>(
            segments: const [
              ButtonSegment(
                value: VanSaleWorkMode.online,
                label: Text('Online'),
                icon: Icon(Icons.cloud_done_outlined, size: 18),
              ),
              ButtonSegment(
                value: VanSaleWorkMode.offline,
                label: Text('Offline'),
                icon: Icon(Icons.cloud_off_outlined, size: 18),
              ),
              ButtonSegment(
                value: VanSaleWorkMode.onlineOffline,
                label: Text('Both'),
                icon: Icon(Icons.sync_alt, size: 18),
              ),
            ],
            selected: {_workMode},
            onSelectionChanged: (s) => setState(() => _workMode = s.first),
          ),
          _sectionTitle(context, 'Stock policy'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow negative stock'),
            subtitle: const Text(
              'Sell or issue below zero on the van (local qty may go negative)',
            ),
            value: _allowNegativeStock,
            onChanged: (v) => setState(() => _allowNegativeStock = v),
          ),
          _sectionTitle(context, 'Sync'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Background sync'),
            subtitle: Text(
              _workMode == VanSaleWorkMode.offline
                  ? 'Disabled while Offline work mode is selected'
                  : 'Every ~45s while signed in',
            ),
            value: _backgroundSync,
            onChanged: _workMode == VanSaleWorkMode.offline
                ? null
                : (v) => setState(() => _backgroundSync = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-sync after write'),
            subtitle: const Text(
              'Online mode always syncs after write. For Online+Offline, '
              'enable this to flush the outbox after each sale.',
            ),
            value: _autoSyncAfterWrite,
            onChanged: _workMode == VanSaleWorkMode.offline
                ? null
                : (v) => setState(() => _autoSyncAfterWrite = v),
          ),
          _sectionTitle(context, 'Alerts'),
          TextField(
            controller: _lowStock,
            decoration: const InputDecoration(
              labelText: 'Low-stock threshold',
              hintText: '5',
              prefixIcon: Icon(Icons.warning_amber_outlined),
              helperText: 'Product chips show low stock at or below this qty',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
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

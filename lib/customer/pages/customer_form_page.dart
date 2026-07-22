import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';
import '../models/customer_model.dart';
import '../repositories/customer_repository.dart';
import '../validation/customer_validators.dart';

/// Full customer create form — saves locally first, syncs when online.
class CustomerFormPage extends StatefulWidget {
  const CustomerFormPage({
    super.key,
    required this.session,
    required this.sync,
  });

  final VanSaleSession session;
  final SyncService sync;

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _draft = CustomerDraft();
  final _picker = ImagePicker();
  CustomerDefaults _defaults = CustomerDefaults.fallback();
  bool _loading = true;
  bool _saving = false;
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final d = await customerRepository.loadDefaults(widget.session);
    _draft.applyDefaults(d);
    if (!mounted) return;
    setState(() {
      _defaults = d;
      _loading = false;
    });
  }

  Future<void> _pickImage(void Function(String path) assign) async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (file == null) return;
      setState(() => assign(file.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick image: $e')),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final created = await customerRepository.createLocal(_draft);
      if (widget.session.connected) {
        try {
          await widget.sync.flush(pullTrips: false);
        } catch (_) {}
      }
      if (!mounted) return;
      final latest = await customerRepository.get(created.id) ?? created;
      if (!mounted) return;
      final synced = latest.syncStatus == SyncStatus.uploaded;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'Customer synced: ${latest.erpName ?? latest.customerName}'
                : 'Customer saved offline (Pending Sync)',
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(latest);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New customer'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Only required fields are shown. Tap More for optional details.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _section('Required'),
                TextFormField(
                  initialValue: _draft.customerName,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name (English) *',
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (v) => _draft.customerName = v,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _draft.customerType,
                  decoration: const InputDecoration(labelText: 'Customer Type'),
                  items: const [
                    DropdownMenuItem(value: 'Company', child: Text('Company')),
                    DropdownMenuItem(
                      value: 'Individual',
                      child: Text('Individual'),
                    ),
                    DropdownMenuItem(
                      value: 'Customer',
                      child: Text('Customer (= Company)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _draft.customerType = v);
                  },
                ),
                _dropdownOrField(
                  label: 'Customer Group *',
                  value: _draft.customerGroup,
                  options: _defaults.customerGroups,
                  onChanged: (v) => setState(() => _draft.customerGroup = v),
                ),
                _dropdownOrField(
                  label: 'Territory *',
                  value: _draft.territory,
                  options: _defaults.territories,
                  onChanged: (v) => setState(() => _draft.territory = v),
                ),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number *',
                  ),
                  keyboardType: TextInputType.phone,
                  onChanged: (v) => _draft.mobileNo = v,
                ),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Address Line 1 *',
                  ),
                  onChanged: (v) => _draft.addressLine1 = v,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'City *'),
                  onChanged: (v) => _draft.city = v,
                ),
                TextFormField(
                  initialValue: _draft.country,
                  decoration: const InputDecoration(labelText: 'Country *'),
                  onChanged: (v) => _draft.country = v,
                ),
                const SizedBox(height: 12),
                _moreButton(),
                Visibility(
                  visible: _showMore,
                  maintainState: true,
                  maintainAnimation: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  const SizedBox(height: 16),
                  _section('Name & business'),
                  TextFormField(
                    initialValue: _draft.customerNameAr,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name Arabic',
                    ),
                    onChanged: (v) => _draft.customerNameAr = v,
                  ),
                  TextFormField(
                    initialValue: _draft.taxId,
                    decoration: const InputDecoration(
                      labelText: 'VAT Number (Tax ID)',
                      hintText: '15 digits starting with 3',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _draft.taxId = v,
                  ),
                  TextFormField(
                    initialValue: _draft.crNumber,
                    decoration: const InputDecoration(
                      labelText: 'Commercial Registration (CR)',
                    ),
                    onChanged: (v) => _draft.crNumber = v,
                  ),
                  TextFormField(
                    initialValue: _draft.customerCode,
                    decoration: const InputDecoration(
                      labelText: 'Customer Code',
                    ),
                    onChanged: (v) => _draft.customerCode = v,
                  ),
                  TextFormField(
                    initialValue: _draft.barcode,
                    decoration: const InputDecoration(
                      labelText: 'Barcode / loyalty card',
                    ),
                    onChanged: (v) => _draft.barcode = v,
                  ),
                  TextFormField(
                    initialValue: _draft.website,
                    decoration: const InputDecoration(labelText: 'Website'),
                    keyboardType: TextInputType.url,
                    onChanged: (v) => _draft.website = v,
                  ),
                  _dropdownOrField(
                    label: 'Industry',
                    value: _draft.industry,
                    options: _defaults.industries,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.industry = v),
                  ),
                  const SizedBox(height: 16),
                  _section('More contact'),
                  TextFormField(
                    initialValue: _draft.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number'),
                    keyboardType: TextInputType.phone,
                    onChanged: (v) => _draft.phone = v,
                  ),
                  TextFormField(
                    initialValue: _draft.email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (v) => _draft.email = v,
                  ),
                  const SizedBox(height: 16),
                  _section('More address'),
                  TextFormField(
                    initialValue: _draft.addressLine2,
                    decoration: const InputDecoration(
                      labelText: 'Address Line 2',
                    ),
                    onChanged: (v) => _draft.addressLine2 = v,
                  ),
                  TextFormField(
                    initialValue: _draft.state,
                    decoration: const InputDecoration(labelText: 'State'),
                    onChanged: (v) => _draft.state = v,
                  ),
                  TextFormField(
                    initialValue: _draft.postalCode,
                    decoration: const InputDecoration(labelText: 'Postal Code'),
                    onChanged: (v) => _draft.postalCode = v,
                  ),
                  TextFormField(
                    initialValue: _draft.googleMapUrl,
                    decoration: const InputDecoration(
                      labelText: 'Google Map Location (URL)',
                    ),
                    onChanged: (v) => _draft.googleMapUrl = v,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _draft.latitude?.toString() ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          onChanged: (v) =>
                              _draft.latitude = double.tryParse(v.trim()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: _draft.longitude?.toString() ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          onChanged: (v) =>
                              _draft.longitude = double.tryParse(v.trim()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _section('Sales'),
                  _dropdownOrField(
                    label: 'Price List',
                    value: _draft.priceList,
                    options: _defaults.priceLists,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.priceList = v),
                  ),
                  _dropdownOrField(
                    label: 'Sales Person',
                    value: _draft.salesPerson,
                    options: _defaults.salesPersons,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.salesPerson = v),
                  ),
                  TextFormField(
                    initialValue: _draft.creditLimit?.toString() ?? '',
                    decoration: const InputDecoration(labelText: 'Credit Limit'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) =>
                        _draft.creditLimit = double.tryParse(v.trim()),
                  ),
                  _dropdownOrField(
                    label: 'Payment Terms Template',
                    value: _draft.paymentTerms,
                    options: _defaults.paymentTermsTemplates,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.paymentTerms = v),
                  ),
                  _dropdownOrField(
                    label: 'Currency',
                    value: _draft.currency,
                    options: _defaults.currencies,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.currency = v),
                  ),
                  const SizedBox(height: 16),
                  _section('Status & notes'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_draft.enabled ? 'Enabled' : 'Disabled'),
                    value: _draft.enabled,
                    onChanged: (v) => setState(() => _draft.enabled = v),
                  ),
                  TextFormField(
                    initialValue: _draft.remarks,
                    decoration: const InputDecoration(labelText: 'Remarks'),
                    maxLines: 3,
                    onChanged: (v) => _draft.remarks = v,
                  ),
                  const SizedBox(height: 16),
                  _section('Attachments'),
                  _attachTile(
                    label: 'Commercial Registration Image',
                    path: _draft.crImagePath,
                    onPick: () => _pickImage((p) => _draft.crImagePath = p),
                    onClear: () => setState(() => _draft.crImagePath = null),
                  ),
                  _attachTile(
                    label: 'VAT Certificate',
                    path: _draft.vatCertificatePath,
                    onPick: () =>
                        _pickImage((p) => _draft.vatCertificatePath = p),
                    onClear: () =>
                        setState(() => _draft.vatCertificatePath = null),
                  ),
                  _attachTile(
                    label: 'Customer Photo',
                    path: _draft.customerPhotoPath,
                    onPick: () =>
                        _pickImage((p) => _draft.customerPhotoPath = p),
                    onClear: () =>
                        setState(() => _draft.customerPhotoPath = null),
                  ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    widget.session.connected
                        ? 'Save & sync'
                        : 'Save offline (Pending Sync)',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _moreButton() {
    return OutlinedButton.icon(
      onPressed: () => setState(() => _showMore = !_showMore),
      icon: Icon(_showMore ? Icons.expand_less : Icons.expand_more),
      label: Text(_showMore ? 'Less' : 'More'),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _dropdownOrField({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    bool allowEmpty = false,
  }) {
    if (options.isEmpty) {
      return TextFormField(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      );
    }
    final items = <String>[
      if (allowEmpty) '',
      ...options,
      if (value.isNotEmpty && !options.contains(value)) value,
    ];
    final selected = items.contains(value)
        ? value
        : (allowEmpty ? '' : items.first);
    if (selected != value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onChanged(selected);
      });
    }
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in items)
          DropdownMenuItem(
            value: o,
            child: Text(o.isEmpty ? '— None —' : o),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _attachTile({
    required String label,
    required String? path,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        path == null || path.isEmpty ? 'No file' : path.split('/').last,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(onPressed: onPick, icon: const Icon(Icons.attach_file)),
          if (path != null && path.isNotEmpty)
            IconButton(onPressed: onClear, icon: const Icon(Icons.clear)),
        ],
      ),
    );
  }
}

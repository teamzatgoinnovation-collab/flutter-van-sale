import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/models.dart';
import '../../services/prefs.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';
import '../validation/product_validators.dart';

class ProductFormPage extends StatefulWidget {
  const ProductFormPage({
    super.key,
    required this.session,
    required this.sync,
  });

  final VanSaleSession session;
  final SyncService sync;

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _draft = ProductDraft();
  final _picker = ImagePicker();
  ProductDefaults _defaults = ProductDefaults.fallback();
  bool _loading = true;
  bool _saving = false;
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final d = await productRepository.loadDefaults(widget.session);
    _draft.applyDefaults(d);
    final wh = VanSalePrefs.instance.warehouse.trim();
    if (_draft.openingWarehouse.isEmpty && wh.isNotEmpty) {
      _draft.openingWarehouse = wh;
    }
    if (!mounted) return;
    setState(() {
      _defaults = d;
      _loading = false;
    });
  }

  Future<void> _pickImage({required bool gallery}) async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (file == null) return;
      setState(() {
        if (gallery) {
          _draft.galleryPaths = [..._draft.galleryPaths, file.path];
        } else {
          _draft.imagePath = file.path;
        }
      });
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
      final created = await productRepository.createLocal(_draft);
      if (widget.session.connected) {
        try {
          await widget.sync.flush(pullTrips: false);
        } catch (_) {}
      }
      if (!mounted) return;
      final latest = await productRepository.get(created.id) ?? created;
      if (!mounted) return;
      final synced = latest.syncStatus == SyncStatus.uploaded;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'Product synced: ${latest.displayCode}'
                : 'Product saved offline (Pending Sync)',
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
        title: const Text('New product'),
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
                  decoration: const InputDecoration(labelText: 'Item Code *'),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (v) => _draft.itemCode = v,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Item Name *'),
                  onChanged: (v) => _draft.itemName = v,
                ),
                _dropdown(
                  label: 'Item Group *',
                  value: _draft.itemGroup,
                  options: _defaults.itemGroups,
                  onChanged: (v) => setState(() => _draft.itemGroup = v),
                ),
                _dropdown(
                  label: 'Stock UOM *',
                  value: _draft.stockUom,
                  options: _defaults.uoms,
                  onChanged: (v) => setState(() {
                    _draft.stockUom = v;
                    if (_draft.salesUom.isEmpty) _draft.salesUom = v;
                  }),
                ),
                _dropdown(
                  label: 'Sales UOM *',
                  value: _draft.salesUom.isEmpty
                      ? _draft.stockUom
                      : _draft.salesUom,
                  options: _defaults.uoms,
                  onChanged: (v) => setState(() => _draft.salesUom = v),
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Selling Rate'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) =>
                      _draft.sellingRate = double.tryParse(v.trim()) ?? 0,
                ),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Opening Quantity',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) =>
                      _draft.openingQuantity = double.tryParse(v.trim()) ?? 0,
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
                  _section('Details'),
                  TextFormField(
                    initialValue: _draft.itemNameAr,
                    decoration: const InputDecoration(
                      labelText: 'Item Name Arabic',
                    ),
                    onChanged: (v) => _draft.itemNameAr = v,
                  ),
                  TextFormField(
                    initialValue: _draft.description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                    onChanged: (v) => _draft.description = v,
                  ),
                  _dropdown(
                    label: 'Brand',
                    value: _draft.brand,
                    options: _defaults.brands,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.brand = v),
                  ),
                  TextFormField(
                    initialValue: _draft.barcode,
                    decoration: const InputDecoration(labelText: 'Barcode'),
                    onChanged: (v) => _draft.barcode = v,
                  ),
                  TextFormField(
                    initialValue: _draft.sku,
                    decoration: const InputDecoration(labelText: 'SKU'),
                    onChanged: (v) => _draft.sku = v,
                  ),
                  TextFormField(
                    initialValue: _draft.hsCode,
                    decoration: const InputDecoration(labelText: 'HS Code'),
                    onChanged: (v) => _draft.hsCode = v,
                  ),
                  const SizedBox(height: 16),
                  _section('Sales & tax'),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Purchase Rate'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) =>
                        _draft.purchaseRate = double.tryParse(v.trim()) ?? 0,
                  ),
                  _dropdown(
                    label: 'Price List',
                    value: _draft.priceList,
                    options: _defaults.priceLists,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.priceList = v),
                  ),
                  _dropdown(
                    label: 'Tax Template',
                    value: _draft.taxTemplate,
                    options: _defaults.itemTaxTemplates,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.taxTemplate = v),
                  ),
                  const SizedBox(height: 16),
                  _section('Inventory'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Maintain Stock'),
                    value: _draft.maintainStock,
                    onChanged: (v) => setState(() => _draft.maintainStock = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_draft.disabled ? 'Disabled' : 'Enabled'),
                    value: !_draft.disabled,
                    onChanged: (v) => setState(() => _draft.disabled = !v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Has Batch'),
                    value: _draft.hasBatch,
                    onChanged: (v) => setState(() => _draft.hasBatch = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Has Serial Number'),
                    value: _draft.hasSerial,
                    onChanged: (v) => setState(() => _draft.hasSerial = v),
                  ),
                  _dropdown(
                    label: 'Opening Warehouse',
                    value: _draft.openingWarehouse,
                    options: _defaults.warehouses,
                    allowEmpty: true,
                    onChanged: (v) =>
                        setState(() => _draft.openingWarehouse = v),
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Reorder Level'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) =>
                        _draft.reorderLevel = double.tryParse(v.trim()),
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Weight'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) => _draft.weight = double.tryParse(v.trim()),
                  ),
                  _dropdown(
                    label: 'Weight UOM',
                    value: _draft.weightUom,
                    options: _defaults.uoms,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.weightUom = v),
                  ),
                  const SizedBox(height: 16),
                  _section('Accounting'),
                  _dropdown(
                    label: 'Income Account',
                    value: _draft.incomeAccount,
                    options: _defaults.incomeAccounts,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.incomeAccount = v),
                  ),
                  _dropdown(
                    label: 'Expense Account',
                    value: _draft.expenseAccount,
                    options: _defaults.expenseAccounts,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.expenseAccount = v),
                  ),
                  _dropdown(
                    label: 'Cost Center',
                    value: _draft.costCenter,
                    options: _defaults.costCenters,
                    allowEmpty: true,
                    onChanged: (v) => setState(() => _draft.costCenter = v),
                  ),
                  const SizedBox(height: 16),
                  _section('Images'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Item Image'),
                    subtitle: Text(
                      _draft.imagePath == null
                          ? 'No file'
                          : _draft.imagePath!.split('/').last,
                    ),
                    trailing: IconButton(
                      onPressed: () => _pickImage(gallery: false),
                      icon: const Icon(Icons.image_outlined),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gallery'),
                    subtitle: Text(
                      _draft.galleryPaths.isEmpty
                          ? 'No files'
                          : '${_draft.galleryPaths.length} file(s)',
                    ),
                    trailing: IconButton(
                      onPressed: () => _pickImage(gallery: true),
                      icon: const Icon(Icons.collections_outlined),
                    ),
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

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _dropdown({
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
}

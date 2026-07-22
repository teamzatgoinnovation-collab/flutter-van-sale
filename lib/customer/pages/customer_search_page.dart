import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../services/sync_service.dart';
import '../models/customer_model.dart';
import '../repositories/customer_repository.dart';
import 'customer_form_page.dart';

/// Offline-first customer search with instant filter, recent, favorites, load more.
class CustomerSearchPage extends StatefulWidget {
  const CustomerSearchPage({
    super.key,
    required this.session,
    this.sync,
    this.selectMode = true,
    this.initialQuery,
  });

  final VanSaleSession session;
  final SyncService? sync;

  /// When true, tapping a row pops with [CustomerModel].
  final bool selectMode;
  final String? initialQuery;

  @override
  State<CustomerSearchPage> createState() => _CustomerSearchPageState();
}

class _CustomerSearchPageState extends State<CustomerSearchPage> {
  static const _pageSize = 30;

  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  CustomerSearchScope _scope = CustomerSearchScope.all;
  List<CustomerModel> _items = const [];
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').isNotEmpty) {
      _query.text = widget.initialQuery!;
    }
    _scroll.addListener(_onScroll);
    _reload(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 120) {
      _loadMore();
    }
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () {
      _reload(reset: true);
    });
  }

  Future<void> _reload({required bool reset}) async {
    if (reset) {
      setState(() => _loading = true);
    }
    final page = await customerRepository.search(
      query: _query.text,
      limit: _pageSize,
      offset: 0,
      scope: _scope,
    );
    if (!mounted) return;
    setState(() {
      _items = page.items;
      _total = page.total;
      _hasMore = page.hasMore;
      _loading = false;
      _refreshing = false;
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    final page = await customerRepository.search(
      query: _query.text,
      limit: _pageSize,
      offset: _items.length,
      scope: _scope,
    );
    if (!mounted) return;
    setState(() {
      _items = [..._items, ...page.items];
      _total = page.total;
      _hasMore = page.hasMore;
      _loadingMore = false;
    });
  }

  Future<void> _pullRefresh() async {
    setState(() => _refreshing = true);
    if (widget.session.connected) {
      try {
        await customerRepository.refreshFromErp(widget.session);
      } catch (_) {}
    }
    await _reload(reset: true);
  }

  Future<void> _barcodeSearch() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barcode / card'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Scan or type barcode',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;

    final hit = await customerRepository.findByBarcode(code);
    if (!mounted) return;
    if (hit != null) {
      await _select(hit);
      return;
    }
    setState(() {
      _scope = CustomerSearchScope.all;
      _query.text = code;
    });
    await _reload(reset: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No exact barcode match for "$code"')),
    );
  }

  Future<void> _select(CustomerModel customer) async {
    await customerRepository.markRecent(customer.id);
    if (!mounted) return;
    if (widget.selectMode) {
      Navigator.of(context).pop(customer);
    }
  }

  Future<void> _toggleFavorite(CustomerModel customer) async {
    final next = !customer.isFavorite;
    await customerRepository.toggleFavorite(customer.id, favorite: next);
    if (!mounted) return;
    setState(() {
      _items = [
        for (final c in _items)
          if (c.id == customer.id) c.copyWith(isFavorite: next) else c,
      ];
    });
  }

  Future<void> _createCustomer() async {
    final sync = widget.sync;
    if (sync == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync service unavailable')),
      );
      return;
    }
    final created = await Navigator.of(context).push<CustomerModel>(
      MaterialPageRoute(
        builder: (_) =>
            CustomerFormPage(session: widget.session, sync: sync),
      ),
    );
    if (created == null || !mounted) return;
    await customerRepository.markRecent(created.id);
    if (widget.selectMode) {
      Navigator.of(context).pop(created);
    } else {
      await _reload(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectMode ? 'Select customer' : 'Customers'),
        actions: [
          IconButton(
            tooltip: 'Barcode search',
            onPressed: _barcodeSearch,
            icon: const Icon(Icons.qr_code_scanner_outlined),
          ),
          IconButton(
            tooltip: 'New customer',
            onPressed: _createCustomer,
            icon: const Icon(Icons.person_add_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _query,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Name, Arabic, phone, VAT, CR, code, email…',
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _query.clear();
                          _reload(reset: true);
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<CustomerSearchScope>(
              segments: const [
                ButtonSegment(
                  value: CustomerSearchScope.all,
                  label: Text('All'),
                  icon: Icon(Icons.people_outline, size: 18),
                ),
                ButtonSegment(
                  value: CustomerSearchScope.recent,
                  label: Text('Recent'),
                  icon: Icon(Icons.history, size: 18),
                ),
                ButtonSegment(
                  value: CustomerSearchScope.favorites,
                  label: Text('Favorites'),
                  icon: Icon(Icons.star_outline, size: 18),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (s) {
                setState(() => _scope = s.first);
                _reload(reset: true);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loading ? 'Searching…' : '$_total customers',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _pullRefresh,
              child: _loading && !_refreshing
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Icon(
                              Icons.person_search_outlined,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                _scope == CustomerSearchScope.favorites
                                    ? 'No favorites yet'
                                    : _scope == CustomerSearchScope.recent
                                        ? 'No recent customers'
                                        : 'No customers match',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                'Pull to refresh · works offline',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _items.length) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : TextButton(
                                          onPressed: _loadMore,
                                          child: const Text('Load more'),
                                        ),
                                ),
                              );
                            }
                            final c = _items[index];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  c.customerName.isEmpty
                                      ? '?'
                                      : c.customerName
                                          .substring(0, 1)
                                          .toUpperCase(),
                                ),
                              ),
                              title: Text(c.displayName),
                              subtitle: Text(
                                [
                                  if ((c.customerNameAr ?? '').isNotEmpty)
                                    c.customerNameAr!,
                                  if (c.subtitle.isNotEmpty) c.subtitle,
                                  if ((c.email ?? '').isNotEmpty) c.email!,
                                  if ((c.crNumber ?? '').isNotEmpty)
                                    'CR ${c.crNumber}',
                                  if ((c.barcode ?? '').isNotEmpty)
                                    'BC ${c.barcode}',
                                ].join('\n'),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: (c.customerNameAr ?? '').isNotEmpty,
                              trailing: IconButton(
                                tooltip: c.isFavorite
                                    ? 'Unfavorite'
                                    : 'Favorite',
                                onPressed: () => _toggleFavorite(c),
                                icon: Icon(
                                  c.isFavorite
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: c.isFavorite
                                      ? theme.colorScheme.primary
                                      : null,
                                ),
                              ),
                              onTap: () => _select(c),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

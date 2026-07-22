import 'package:flutter/material.dart';

import '../../core/search/search_list_controller.dart';
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
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _controller = SearchListController<CustomerModel>();

  CustomerSearchScope _scope = CustomerSearchScope.all;

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').isNotEmpty) {
      _query.text = widget.initialQuery!;
      _controller.query = widget.initialQuery!;
    }
    _controller.runSearch =
        ({required String query, required int limit, required int offset}) {
          return customerRepository.search(
            query: query,
            limit: limit,
            offset: offset,
            scope: _scope,
          );
        };
    _controller.addListener(_onController);
    _scroll.addListener(_onScroll);
    _controller.reload(reset: true);
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _controller.disposeController();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 120) {
      _controller.loadMore();
    }
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
          decoration: const InputDecoration(hintText: 'Scan or type barcode'),
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
    setState(() => _scope = CustomerSearchScope.all);
    _query.text = code;
    _controller.query = code;
    await _controller.reload(reset: true);
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
    _controller.items = [
      for (final c in _controller.items)
        if (c.id == customer.id) c.copyWith(isFavorite: next) else c,
    ];
    setState(() {});
  }

  Future<void> _createCustomer() async {
    final sync = widget.sync;
    if (sync == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync service unavailable')));
      return;
    }
    final created = await Navigator.of(context).push<CustomerModel>(
      MaterialPageRoute(
        builder: (_) => CustomerFormPage(session: widget.session, sync: sync),
      ),
    );
    if (created == null || !mounted) return;
    await customerRepository.markRecent(created.id);
    if (!mounted) return;
    if (widget.selectMode) {
      Navigator.of(context).pop(created);
    } else {
      await _controller.reload(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _controller;
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
              onChanged: _controller.onQueryChanged,
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
                          _controller.clearQuery();
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
                _controller.reload(reset: true);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                c.loading ? 'Searching…' : '${c.total} customers',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _controller.pullRefresh(
                widget.session.connected
                    ? () => customerRepository.refreshFromErp(widget.session)
                    : null,
              ),
              child: c.loading && !c.refreshing
                  ? const Center(child: CircularProgressIndicator())
                  : c.items.isEmpty
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
                      itemCount: c.items.length + (c.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= c.items.length) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: c.loadingMore
                                  ? const CircularProgressIndicator()
                                  : TextButton(
                                      onPressed: _controller.loadMore,
                                      child: const Text('Load more'),
                                    ),
                            ),
                          );
                        }
                        final customer = c.items[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              customer.customerName.isEmpty
                                  ? '?'
                                  : customer.customerName
                                        .substring(0, 1)
                                        .toUpperCase(),
                            ),
                          ),
                          title: Text(customer.displayName),
                          subtitle: Text(
                            [
                              if ((customer.customerNameAr ?? '').isNotEmpty)
                                customer.customerNameAr!,
                              if (customer.subtitle.isNotEmpty)
                                customer.subtitle,
                              if ((customer.email ?? '').isNotEmpty)
                                customer.email!,
                              if ((customer.crNumber ?? '').isNotEmpty)
                                'CR ${customer.crNumber}',
                              if ((customer.barcode ?? '').isNotEmpty)
                                'BC ${customer.barcode}',
                            ].join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine:
                              (customer.customerNameAr ?? '').isNotEmpty,
                          trailing: IconButton(
                            tooltip: customer.isFavorite
                                ? 'Unfavorite'
                                : 'Favorite',
                            onPressed: () => _toggleFavorite(customer),
                            icon: Icon(
                              customer.isFavorite
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: customer.isFavorite
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                          onTap: () => _select(customer),
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

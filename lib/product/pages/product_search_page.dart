import 'package:flutter/material.dart';

import '../../core/search/search_list_controller.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';
import '../../services/van_sale_policy.dart';
import '../../widgets/widgets.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';
import '../widgets/product_thumb.dart';
import 'product_form_page.dart';

/// Offline-first product search with stock/price indicators and infinite scroll.
class ProductSearchPage extends StatefulWidget {
  const ProductSearchPage({
    super.key,
    required this.session,
    this.sync,
    this.selectMode = true,
    this.initialQuery,
  });

  final VanSaleSession session;
  final SyncService? sync;
  final bool selectMode;
  final String? initialQuery;

  @override
  State<ProductSearchPage> createState() => _ProductSearchPageState();
}

class _ProductSearchPageState extends State<ProductSearchPage> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _controller = SearchListController<ProductModel>();

  ProductSearchScope _scope = ProductSearchScope.all;

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').isNotEmpty) {
      _query.text = widget.initialQuery!;
      _controller.query = widget.initialQuery!;
    }
    _controller.runSearch =
        ({required String query, required int limit, required int offset}) {
          return productRepository.search(
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
        title: const Text('Scan barcode'),
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
    final hit = await productRepository.findByBarcode(code);
    if (!mounted) return;
    if (hit != null) {
      await _select(hit);
      return;
    }
    setState(() => _scope = ProductSearchScope.all);
    _query.text = code;
    _controller.query = code;
    await _controller.reload(reset: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No exact barcode match for "$code"')),
    );
  }

  Future<void> _select(ProductModel product) async {
    await productRepository.markRecent(product.id);
    if (!mounted) return;
    if (widget.selectMode) {
      Navigator.of(context).pop(product);
    }
  }

  Future<void> _toggleFavorite(ProductModel product) async {
    final next = !product.isFavorite;
    await productRepository.toggleFavorite(product.id, favorite: next);
    if (!mounted) return;
    _controller.items = [
      for (final p in _controller.items)
        if (p.id == product.id) p.copyWith(isFavorite: next) else p,
    ];
    setState(() {});
  }

  Future<void> _createProduct() async {
    final sync = widget.sync;
    if (sync == null) return;
    final created = await Navigator.of(context).push<ProductModel>(
      MaterialPageRoute(
        builder: (_) => ProductFormPage(session: widget.session, sync: sync),
      ),
    );
    if (created == null || !mounted) return;
    await productRepository.markRecent(created.id);
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
        title: Text(widget.selectMode ? 'Select product' : 'Products'),
        actions: [
          IconButton(
            tooltip: 'Barcode',
            onPressed: _barcodeSearch,
            icon: const Icon(Icons.qr_code_scanner_outlined),
          ),
          IconButton(
            tooltip: 'New product',
            onPressed: _createProduct,
            icon: const Icon(Icons.add_box_outlined),
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
                hintText: 'Code, name, Arabic, barcode, SKU, brand…',
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _query.clear();
                          _controller.clearQuery();
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<ProductSearchScope>(
              segments: const [
                ButtonSegment(
                  value: ProductSearchScope.all,
                  label: Text('All'),
                  icon: Icon(Icons.inventory_2_outlined, size: 18),
                ),
                ButtonSegment(
                  value: ProductSearchScope.recent,
                  label: Text('Recent'),
                  icon: Icon(Icons.history, size: 18),
                ),
                ButtonSegment(
                  value: ProductSearchScope.frequent,
                  label: Text('Frequent'),
                  icon: Icon(Icons.trending_up, size: 18),
                ),
                ButtonSegment(
                  value: ProductSearchScope.favorites,
                  label: Text('Fav'),
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
                c.loading ? 'Searching…' : '${c.total} products',
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
                    ? () => productRepository.refreshFromErp(widget.session)
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
                          Icons.search_off,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            _scope == ProductSearchScope.favorites
                                ? 'No favorites yet'
                                : _scope == ProductSearchScope.recent
                                ? 'No recent products'
                                : _scope == ProductSearchScope.frequent
                                ? 'No sales history yet'
                                : 'No products match',
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
                        final p = c.items[index];
                        return ListTile(
                          leading: ProductThumb(path: p.imagePath),
                          title: Text(p.itemName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((p.itemNameAr ?? '').isNotEmpty)
                                Text(p.itemNameAr!),
                              Text(
                                p.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _StockChip(product: p),
                                  _PriceChip(product: p),
                                ],
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: p.isFavorite ? 'Unfavorite' : 'Favorite',
                            onPressed: () => _toggleFavorite(p),
                            icon: Icon(
                              p.isFavorite
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: p.isFavorite
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                          onTap: () => _select(p),
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

class _StockChip extends StatelessWidget {
  const _StockChip({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final String label;
    if (!product.inStock) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
      label = 'Out of stock';
    } else if (product.isLowStock(
      threshold: VanSalePolicy.instance.lowStockThreshold,
    )) {
      bg = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
      label = 'Low ${money(product.stockQty)} ${product.stockUom}';
    } else {
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
      label = '${money(product.stockQty)} ${product.stockUom}';
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      backgroundColor: bg,
      label: Text(label, style: TextStyle(color: fg, fontSize: 12)),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      backgroundColor: scheme.primaryContainer,
      label: Text(
        money(product.displayPrice),
        style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'paged_search_result.dart';

/// Shared debounce + pagination state for offline search screens.
///
/// Business search logic stays in subclasses via [runSearch].
class SearchListController<T> extends ChangeNotifier {
  SearchListController({
    this.pageSize = 30,
    this.debounce = const Duration(milliseconds: 160),
  });

  final int pageSize;
  final Duration debounce;

  String query = '';
  List<T> items = const [];
  int total = 0;
  bool hasMore = false;
  bool loading = true;
  bool loadingMore = false;
  bool refreshing = false;

  Timer? _debounceTimer;

  Future<PagedSearchResult<T>> Function({
    required String query,
    required int limit,
    required int offset,
  })? runSearch;

  void disposeController() {
    _debounceTimer?.cancel();
  }

  void onQueryChanged(String value) {
    query = value;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      unawaited(reload(reset: true));
    });
    notifyListeners();
  }

  void clearQuery() {
    query = '';
    notifyListeners();
    unawaited(reload(reset: true));
  }

  Future<void> reload({required bool reset}) async {
    final search = runSearch;
    if (search == null) return;
    if (reset) {
      loading = true;
      notifyListeners();
    }
    try {
      final page = await search(query: query, limit: pageSize, offset: 0);
      items = page.items;
      total = page.total;
      hasMore = page.hasMore;
    } finally {
      loading = false;
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final search = runSearch;
    if (search == null || !hasMore || loadingMore || loading) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await search(
        query: query,
        limit: pageSize,
        offset: items.length,
      );
      items = [...items, ...page.items];
      total = page.total;
      hasMore = page.hasMore;
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> pullRefresh(Future<void> Function()? beforeReload) async {
    refreshing = true;
    notifyListeners();
    try {
      if (beforeReload != null) await beforeReload();
    } catch (_) {
      // Preserve prior offline behavior: refresh failures are non-fatal.
    }
    await reload(reset: true);
  }
}

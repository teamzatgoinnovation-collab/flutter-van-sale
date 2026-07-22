/// Paginated offline search result shared by Customer and Product.
class PagedSearchResult<T> {
  const PagedSearchResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  final List<T> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  PagedSearchResult<T> append(PagedSearchResult<T> next) {
    return PagedSearchResult<T>(
      items: [...items, ...next.items],
      total: next.total,
      limit: next.limit,
      offset: next.offset,
      hasMore: next.hasMore,
    );
  }
}

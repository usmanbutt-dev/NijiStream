/// NijiStream — Riverpod providers for extension state management.
///
/// These providers manage the extension lifecycle state and expose it reactively
/// to the UI. When extensions are loaded/searched, widgets automatically rebuild.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../extensions/api/extension_api.dart';
import '../../extensions/models/extension_manifest.dart';
import '../../extensions/repository/extension_repository.dart';

/// Sentinel value used in copyWith() to distinguish "not provided" from null.
const _absent = Object();

// ═══════════════════════════════════════════════════════════════════
// Extension initialization state
// ═══════════════════════════════════════════════════════════════════

/// Manages the extension system initialization and loaded extensions list.
class ExtensionNotifier extends StateNotifier<ExtensionState> {
  final ExtensionRepository _repo;

  ExtensionNotifier(this._repo) : super(const ExtensionState());

  /// Initialize the extension system and load all installed extensions.
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.init();
      final manifests = await _repo.loadAllExtensions();
      state = state.copyWith(
        isLoading: false,
        loadedExtensions: manifests,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Install an extension from a repo entry, then reload.
  Future<void> installExtension(ExtensionRepoEntry entry) async {
    try {
      final filePath = await _repo.installExtension(entry);
      final manifest = await _repo.loadExtension(entry.id, filePath);
      if (manifest != null) {
        state = state.copyWith(
          loadedExtensions: [...state.loadedExtensions, manifest],
        );
      }
    } catch (e) {
      state = state.copyWith(error: 'Install failed: $e');
    }
  }

  /// Remove an extension and reload state.
  Future<void> removeExtension(String extensionId) async {
    try {
      await _repo.removeExtension(extensionId);
      state = state.copyWith(
        loadedExtensions: state.loadedExtensions
            .where((m) => m.id != extensionId)
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Remove failed: $e');
    }
  }

  /// Fetch a repo index from a URL.
  Future<ExtensionRepo?> fetchRepo(String url) async {
    try {
      return await _repo.fetchRepoIndex(url);
    } catch (e) {
      state = state.copyWith(error: 'Failed to fetch repo: $e');
      return null;
    }
  }
}

/// Immutable state for the extension system.
class ExtensionState {
  final bool isLoading;
  final List<ExtensionManifest> loadedExtensions;
  final String? error;

  const ExtensionState({
    this.isLoading = false,
    this.loadedExtensions = const [],
    this.error,
  });

  ExtensionState copyWith({
    bool? isLoading,
    List<ExtensionManifest>? loadedExtensions,
    Object? error = _absent,
  }) {
    return ExtensionState(
      isLoading: isLoading ?? this.isLoading,
      loadedExtensions: loadedExtensions ?? this.loadedExtensions,
      error: error == _absent ? this.error : error as String?,
    );
  }
}

/// Provider for the extension state notifier.
final extensionNotifierProvider =
    StateNotifierProvider<ExtensionNotifier, ExtensionState>((ref) {
  final repo = ref.read(extensionRepositoryProvider);
  return ExtensionNotifier(repo);
});

// ═══════════════════════════════════════════════════════════════════
// Search state
// ═══════════════════════════════════════════════════════════════════

/// Manages search state across all loaded extensions.
class SearchNotifier extends StateNotifier<SearchState> {
  final ExtensionRepository _repo;

  SearchNotifier(this._repo) : super(const SearchState());

  /// Search all loaded extensions for a query.
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    state = state.copyWith(isSearching: true, query: query, currentPage: 1, clearResults: true);

    try {
      final results = await _repo.searchAll(query, 1);

      // Flatten results from all extensions into a single list.
      final allResults = <SearchResultWithSource>[];
      for (final entry in results.entries) {
        final manifest = _repo.getManifest(entry.key);
        for (final result in entry.value.results) {
          allResults.add(SearchResultWithSource(
            result: result,
            extensionId: entry.key,
            extensionName: manifest?.name ?? entry.key,
          ));
        }
      }

      // If any extension returned results, assume more pages may exist.
      final hasMore = allResults.isNotEmpty;

      state = state.copyWith(
        isSearching: false,
        results: allResults,
        hasResults: true,
        currentPage: 1,
        canLoadMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        error: e.toString(),
      );
    }
  }

  /// Load the next page of search results and append to the current list.
  Future<void> loadMore() async {
    if (state.isSearching || !state.canLoadMore || state.query.isEmpty) return;

    final nextPage = state.currentPage + 1;
    state = state.copyWith(isLoadingMore: true);

    try {
      final results = await _repo.searchAll(state.query, nextPage);

      final newResults = <SearchResultWithSource>[];
      for (final entry in results.entries) {
        final manifest = _repo.getManifest(entry.key);
        for (final result in entry.value.results) {
          newResults.add(SearchResultWithSource(
            result: result,
            extensionId: entry.key,
            extensionName: manifest?.name ?? entry.key,
          ));
        }
      }

      state = state.copyWith(
        isLoadingMore: false,
        results: [...state.results, ...newResults],
        currentPage: nextPage,
        canLoadMore: newResults.isNotEmpty,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Filter results to a specific extension (null = all).
  void setSourceFilter(String? extensionId) {
    state = state.copyWith(
      sourceFilter: extensionId,
      clearSourceFilter: extensionId == null,
    );
  }

  /// Change the sort order of the current results.
  void setSortOrder(SearchSortOrder order) {
    state = state.copyWith(sortOrder: order);
  }

  /// Load popular anime from all extensions (shown on browse screen open).
  Future<void> loadPopular() async {
    if (_repo.loadedCount == 0) return;

    state = state.copyWith(isSearching: true);

    try {
      final results = <SearchResultWithSource>[];
      for (final id in _repo.loadedExtensionIds) {
        try {
          final resp = await _repo.getPopular(id, 1);
          if (resp != null) {
            final manifest = _repo.getManifest(id);
            for (final r in resp.results) {
              results.add(SearchResultWithSource(
                result: r,
                extensionId: id,
                extensionName: manifest?.name ?? id,
              ));
            }
          }
        } catch (_) {}
      }
      state = state.copyWith(
        isSearching: false,
        results: results,
        hasResults: results.isNotEmpty,
        query: '',
      );
    } catch (_) {
      state = state.copyWith(isSearching: false);
    }
  }

  /// Clear search results.
  void clear() {
    state = const SearchState();
  }
}

/// A search result tagged with its source extension.
class SearchResultWithSource {
  final ExtensionSearchResult result;
  final String extensionId;
  final String extensionName;

  const SearchResultWithSource({
    required this.result,
    required this.extensionId,
    required this.extensionName,
  });
}

/// Sort order for search results.
enum SearchSortOrder { relevance, titleAsc, titleDesc, source }

/// Immutable search state.
class SearchState {
  final bool isSearching;
  final String query;

  /// All unfiltered results across all extensions.
  final List<SearchResultWithSource> results;

  final bool hasResults;
  final String? error;

  /// null = show all sources; otherwise only this extensionId.
  final String? sourceFilter;

  final SearchSortOrder sortOrder;

  /// The last page number that was fetched.
  final int currentPage;

  /// Whether more pages may be available.
  final bool canLoadMore;

  /// True while a loadMore() call is in flight (doesn't block the grid).
  final bool isLoadingMore;

  const SearchState({
    this.isSearching = false,
    this.query = '',
    this.results = const [],
    this.hasResults = false,
    this.error,
    this.sourceFilter,
    this.sortOrder = SearchSortOrder.relevance,
    this.currentPage = 1,
    this.canLoadMore = false,
    this.isLoadingMore = false,
  });

  /// Results after applying [sourceFilter] and [sortOrder].
  List<SearchResultWithSource> get filteredResults {
    var list = results;

    // Source filter
    if (sourceFilter != null) {
      list = list.where((r) => r.extensionId == sourceFilter).toList();
    }

    // Sort
    switch (sortOrder) {
      case SearchSortOrder.titleAsc:
        list = [...list]
          ..sort((a, b) => a.result.title.compareTo(b.result.title));
      case SearchSortOrder.titleDesc:
        list = [...list]
          ..sort((a, b) => b.result.title.compareTo(a.result.title));
      case SearchSortOrder.source:
        list = [...list]
          ..sort((a, b) => a.extensionName.compareTo(b.extensionName));
      case SearchSortOrder.relevance:
        break; // keep original order
    }

    return list;
  }

  /// Unique extension IDs present in current results.
  List<String> get availableSourceIds =>
      results.map((r) => r.extensionId).toSet().toList();

  SearchState copyWith({
    bool? isSearching,
    String? query,
    List<SearchResultWithSource>? results,
    bool? hasResults,
    Object? error = _absent,
    String? sourceFilter,
    bool clearSourceFilter = false,
    SearchSortOrder? sortOrder,
    int? currentPage,
    bool? canLoadMore,
    bool? isLoadingMore,
    bool clearResults = false,
  }) {
    return SearchState(
      isSearching: isSearching ?? this.isSearching,
      query: query ?? this.query,
      results: clearResults ? const [] : (results ?? this.results),
      hasResults: hasResults ?? this.hasResults,
      error: error == _absent ? this.error : error as String?,
      sourceFilter: clearSourceFilter ? null : (sourceFilter ?? this.sourceFilter),
      sortOrder: sortOrder ?? this.sortOrder,
      currentPage: currentPage ?? this.currentPage,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Provider for the search state notifier.
final searchNotifierProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final repo = ref.read(extensionRepositoryProvider);
  return SearchNotifier(repo);
});

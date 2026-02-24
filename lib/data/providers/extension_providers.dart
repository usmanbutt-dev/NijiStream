/// NijiStream — Riverpod providers for extension state management.
///
/// These providers manage the extension lifecycle state and expose it reactively
/// to the UI. When extensions are loaded/searched, widgets automatically rebuild.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../extensions/api/extension_api.dart';
import '../../extensions/models/extension_manifest.dart';
import '../../extensions/repository/extension_repository.dart';

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
    String? error,
  }) {
    return ExtensionState(
      isLoading: isLoading ?? this.isLoading,
      loadedExtensions: loadedExtensions ?? this.loadedExtensions,
      error: error,
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

    state = state.copyWith(isSearching: true, query: query);

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

      state = state.copyWith(
        isSearching: false,
        results: allResults,
        hasResults: true,
      );
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        error: e.toString(),
      );
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

  const SearchState({
    this.isSearching = false,
    this.query = '',
    this.results = const [],
    this.hasResults = false,
    this.error,
    this.sourceFilter,
    this.sortOrder = SearchSortOrder.relevance,
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
    String? error,
    String? sourceFilter,
    bool clearSourceFilter = false,
    SearchSortOrder? sortOrder,
  }) {
    return SearchState(
      isSearching: isSearching ?? this.isSearching,
      query: query ?? this.query,
      results: results ?? this.results,
      hasResults: hasResults ?? this.hasResults,
      error: error,
      sourceFilter: clearSourceFilter ? null : (sourceFilter ?? this.sourceFilter),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

/// Provider for the search state notifier.
final searchNotifierProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final repo = ref.read(extensionRepositoryProvider);
  return SearchNotifier(repo);
});

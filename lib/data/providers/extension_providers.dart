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

/// Immutable search state.
class SearchState {
  final bool isSearching;
  final String query;
  final List<SearchResultWithSource> results;
  final bool hasResults;
  final String? error;

  const SearchState({
    this.isSearching = false,
    this.query = '',
    this.results = const [],
    this.hasResults = false,
    this.error,
  });

  SearchState copyWith({
    bool? isSearching,
    String? query,
    List<SearchResultWithSource>? results,
    bool? hasResults,
    String? error,
  }) {
    return SearchState(
      isSearching: isSearching ?? this.isSearching,
      query: query ?? this.query,
      results: results ?? this.results,
      hasResults: hasResults ?? this.hasResults,
      error: error,
    );
  }
}

/// Provider for the search state notifier.
final searchNotifierProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final repo = ref.read(extensionRepositoryProvider);
  return SearchNotifier(repo);
});

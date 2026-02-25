/// NijiStream — Browse / Search screen.
///
/// This is the primary discovery screen. It features:
/// - A search bar in the app bar
/// - Source filter chips (one per loaded extension) + an "All" chip
/// - A sort dropdown (relevance, A→Z, Z→A, by source)
/// - A responsive grid of anime results
/// - Pull-to-refresh for re-querying
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../data/providers/extension_providers.dart';
import '../../extensions/models/extension_manifest.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _popularLoaded = false;
  int _lastExtensionCount = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    ref.read(searchNotifierProvider.notifier).search(query);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    // After clearing, reload popular so the grid repopulates.
    _popularLoaded = false;
    ref.read(searchNotifierProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extensionState = ref.watch(extensionNotifierProvider);
    final searchState = ref.watch(searchNotifierProvider);

    // Reset _popularLoaded whenever the extension count changes so that
    // installing or removing an extension refreshes the popular grid.
    final currentCount = extensionState.loadedExtensions.length;
    if (currentCount != _lastExtensionCount) {
      _lastExtensionCount = currentCount;
      _popularLoaded = false;
    }

    // Once extensions finish loading, auto-fetch popular content.
    if (!extensionState.isLoading &&
        extensionState.loadedExtensions.isNotEmpty &&
        !_popularLoaded &&
        !searchState.hasResults &&
        searchState.query.isEmpty) {
      _popularLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(searchNotifierProvider.notifier).loadPopular();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: _SearchBar(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onSearch: _onSearch,
          onClear: _clearSearch,
          isSearching: searchState.isSearching,
        ),
        toolbarHeight: 64,
        // Show filter row only when there are results
        bottom: searchState.hasResults && !searchState.isSearching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: _FilterRow(
                  searchState: searchState,
                  loadedExtensions: extensionState.loadedExtensions,
                ),
              )
            : null,
      ),
      body: _buildBody(theme, extensionState, searchState),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    ExtensionState extState,
    SearchState searchState,
  ) {
    // Loading state
    if (extState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // No extensions installed
    if (extState.loadedExtensions.isEmpty) {
      return _NoExtensionsView(theme: theme);
    }

    // Active search
    if (searchState.isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching extensions...'),
          ],
        ),
      );
    }

    // Search results (filtered)
    if (searchState.hasResults) {
      final filtered = searchState.filteredResults;
      if (filtered.isEmpty) {
        return _NoResultsView(
          theme: theme,
          query: searchState.query,
          hasSourceFilter: searchState.sourceFilter != null,
        );
      }
      return _AnimeGrid(results: filtered);
    }

    // Default: only reached if extension has no getPopular().
    return _DefaultBrowseView(theme: theme);
  }
}

// ═══════════════════════════════════════════════════════════════════
// Filter Row — source chips + sort button
// ═══════════════════════════════════════════════════════════════════

class _FilterRow extends ConsumerWidget {
  final SearchState searchState;
  final List<ExtensionManifest> loadedExtensions;

  const _FilterRow({
    required this.searchState,
    required this.loadedExtensions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(searchNotifierProvider.notifier);
    final theme = Theme.of(context);

    // Build a name map from loaded extensions
    final nameMap = {for (final m in loadedExtensions) m.id: m.name};

    return SizedBox(
      height: 44,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          // ── "All sources" chip ──
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
            child: ChoiceChip(
              label: const Text('All'),
              selected: searchState.sourceFilter == null,
              onSelected: (_) => notifier.setSourceFilter(null),
              selectedColor: theme.colorScheme.primaryContainer,
              labelStyle: TextStyle(
                color: searchState.sourceFilter == null
                    ? theme.colorScheme.primary
                    : NijiColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),

          // ── Per-source chips ──
          ...searchState.availableSourceIds.map((id) {
            final isSelected = searchState.sourceFilter == id;
            return Padding(
              padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              child: ChoiceChip(
                label: Text(nameMap[id] ?? id),
                selected: isSelected,
                onSelected: (_) =>
                    notifier.setSourceFilter(isSelected ? null : id),
                selectedColor: theme.colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : NijiColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            );
          }),

          // ── Sort button ──
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6, bottom: 6),
            child: _SortButton(sortOrder: searchState.sortOrder),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Sort Button
// ═══════════════════════════════════════════════════════════════════

class _SortButton extends ConsumerWidget {
  final SearchSortOrder sortOrder;

  const _SortButton({required this.sortOrder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(searchNotifierProvider.notifier);
    final theme = Theme.of(context);

    return PopupMenuButton<SearchSortOrder>(
      initialValue: sortOrder,
      onSelected: notifier.setSortOrder,
      color: NijiColors.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: NijiColors.divider),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 14, color: NijiColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              _sortLabel(sortOrder),
              style: theme.textTheme.labelSmall?.copyWith(
                color: NijiColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        _sortItem(SearchSortOrder.relevance, 'Relevance', Icons.star_rounded),
        _sortItem(SearchSortOrder.titleAsc, 'Title A→Z', Icons.sort_by_alpha_rounded),
        _sortItem(SearchSortOrder.titleDesc, 'Title Z→A', Icons.sort_by_alpha_rounded),
        _sortItem(SearchSortOrder.source, 'By Source', Icons.extension_rounded),
      ],
    );
  }

  PopupMenuItem<SearchSortOrder> _sortItem(
    SearchSortOrder order,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem(
      value: order,
      child: Row(
        children: [
          Icon(icon, size: 16, color: NijiColors.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  String _sortLabel(SearchSortOrder order) => switch (order) {
        SearchSortOrder.relevance => 'Relevance',
        SearchSortOrder.titleAsc => 'A→Z',
        SearchSortOrder.titleDesc => 'Z→A',
        SearchSortOrder.source => 'Source',
      };
}

// ═══════════════════════════════════════════════════════════════════
// Search Bar
// ═══════════════════════════════════════════════════════════════════

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;
  final bool isSearching;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onSearch,
    required this.onClear,
    required this.isSearching,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: NijiColors.surfaceVariant,
        borderRadius: BorderRadius.circular(22),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: onSearch,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search anime...',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: NijiColors.textTertiary,
          ),
          prefixIcon: isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search_rounded, color: NijiColors.textSecondary),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: NijiColors.textSecondary,
                  onPressed: onClear,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Anime Grid
// ═══════════════════════════════════════════════════════════════════

class _AnimeGrid extends ConsumerWidget {
  final List<SearchResultWithSource> results;

  const _AnimeGrid({required this.results});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchNotifierProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 4
                : constraints.maxWidth > 400
                    ? 3
                    : 2;

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _AnimeCard(result: results[index]),
                  childCount: results.length,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
              ),
            ),

            // ── Pagination footer ──
            if (searchState.canLoadMore || searchState.isLoadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: searchState.isLoadingMore
                        ? const CircularProgressIndicator()
                        : TextButton.icon(
                            onPressed: () => ref
                                .read(searchNotifierProvider.notifier)
                                .loadMore(),
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('Load more'),
                          ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Anime Card
// ═══════════════════════════════════════════════════════════════════

class _AnimeCard extends StatelessWidget {
  final SearchResultWithSource result;

  const _AnimeCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        context.push(
          '/anime/${Uri.encodeComponent(result.extensionId)}/${Uri.encodeComponent(result.result.id)}',
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover Image ──
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                color: NijiColors.surfaceVariant,
                child: result.result.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: result.result.coverUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => _CoverPlaceholder(
                          title: result.result.title,
                        ),
                        errorWidget: (context, url, error) => _CoverPlaceholder(
                          title: result.result.title,
                        ),
                      )
                    : _CoverPlaceholder(title: result.result.title),
              ),
            ),
          ),

          // ── Title ──
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
            child: Text(
              result.result.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // ── Source label ──
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2, top: 2),
            child: Text(
              result.extensionName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for covers that haven't loaded yet.
class _CoverPlaceholder extends StatelessWidget {
  final String title;
  const _CoverPlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NijiColors.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 40,
          color: NijiColors.textTertiary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Empty / Default States
// ═══════════════════════════════════════════════════════════════════

class _NoExtensionsView extends StatelessWidget {
  final ThemeData theme;
  const _NoExtensionsView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.extension_off_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No extensions installed',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Go to Settings → Extensions to add\nsources and start browsing anime.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: NijiColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsView extends StatelessWidget {
  final ThemeData theme;
  final String query;
  final bool hasSourceFilter;
  const _NoResultsView({
    required this.theme,
    required this.query,
    required this.hasSourceFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text('No results for "$query"', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            hasSourceFilter
                ? 'No results from this source.\nTry switching to "All" sources.'
                : 'Try a different search term or add more extensions.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: NijiColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DefaultBrowseView extends StatelessWidget {
  final ThemeData theme;
  const _DefaultBrowseView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.explore_rounded,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Search for anime',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Type in the search bar to find anime\nacross all your installed extensions.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: NijiColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

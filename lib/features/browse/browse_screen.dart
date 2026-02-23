/// NijiStream — Browse / Search screen.
///
/// This is the primary discovery screen. It features:
/// - A search bar in the app bar
/// - A grid of anime results from loaded extensions
/// - Empty states for no extensions or no results
/// - Pull-to-refresh for re-querying
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../data/providers/extension_providers.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

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
    ref.read(searchNotifierProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extensionState = ref.watch(extensionNotifierProvider);
    final searchState = ref.watch(searchNotifierProvider);

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

    // Search results
    if (searchState.hasResults) {
      if (searchState.results.isEmpty) {
        return _NoResultsView(theme: theme, query: searchState.query);
      }
      return _AnimeGrid(results: searchState.results);
    }

    // Default: prompt to search
    return _DefaultBrowseView(theme: theme);
  }
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

class _AnimeGrid extends StatelessWidget {
  final List<SearchResultWithSource> results;

  const _AnimeGrid({required this.results});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive grid: more columns on wider screens
        final crossAxisCount = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 4
                : constraints.maxWidth > 400
                    ? 3
                    : 2;

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.55,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: results.length,
          itemBuilder: (context, index) => _AnimeCard(
            result: results[index],
          ),
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
        // Navigate to anime detail, passing extension ID and anime ID.
        context.push(
          '/anime/${result.extensionId}/${result.result.id}',
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
                        placeholder: (_, url) => _CoverPlaceholder(
                          title: result.result.title,
                        ),
                        errorWidget: (_, url, error) => _CoverPlaceholder(
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
  const _NoResultsView({required this.theme, required this.query});

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
            'Try a different search term or add more extensions.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: NijiColors.textSecondary,
            ),
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

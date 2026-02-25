/// NijiStream — Library screen.
///
/// Displays the user's anime collection organized by watch status.
/// Backed by the drift SQLite database via [LibraryRepository].
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/library_repository.dart';

// ── Providers ────────────────────────────────────────────────────────────────

/// Reactive stream of all library items (for the "All" tab).
final _allLibraryProvider = StreamProvider<List<LibraryItem>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchLibrary();
});

/// Reactive stream filtered by a specific [status].
final _filteredLibraryProvider =
    StreamProvider.family<List<LibraryItem>, String>((ref, status) {
  return ref.watch(libraryRepositoryProvider).watchLibrary(status: status);
});

// ═══════════════════════════════════════════════════════════════════
// Library Screen
// ═══════════════════════════════════════════════════════════════════

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabCount = LibraryStatus.all.length + 1; // +1 for "All"
    final theme = Theme.of(context);

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: NijiColors.textSecondary,
            tabs: [
              const Tab(text: 'All'),
              ...LibraryStatus.all
                  .map((s) => Tab(text: LibraryStatus.label(s))),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // "All" tab
            const _AllLibraryTab(),
            // Per-status tabs
            ...LibraryStatus.all.map((s) => _FilteredLibraryTab(status: s)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Library Tabs
// ═══════════════════════════════════════════════════════════════════

class _AllLibraryTab extends ConsumerWidget {
  const _AllLibraryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _buildFromAsync(ref.watch(_allLibraryProvider));
  }
}

class _FilteredLibraryTab extends ConsumerWidget {
  final String status;
  const _FilteredLibraryTab({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _buildFromAsync(ref.watch(_filteredLibraryProvider(status)));
  }
}

Widget _buildFromAsync(AsyncValue<List<LibraryItem>> async) {
  return async.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) =>
        Center(child: Text('Error: $e', style: const TextStyle(color: NijiColors.error))),
    data: (items) {
      if (items.isEmpty) return const _EmptyLibraryView();
      return _LibraryGrid(items: items);
    },
  );
}

// ═══════════════════════════════════════════════════════════════════
// Library Grid
// ═══════════════════════════════════════════════════════════════════

class _LibraryGrid extends StatelessWidget {
  final List<LibraryItem> items;

  const _LibraryGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = MediaQuery.sizeOf(context).width > 600 ? 4 : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.6,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _LibraryCard(item: items[index]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Library Card
// ═══════════════════════════════════════════════════════════════════

class _LibraryCard extends StatelessWidget {
  final LibraryItem item;

  const _LibraryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anime = item.anime;
    final library = item.library;

    // Extract extensionId and animeId from the composite DB id: "{extensionId}:{animeId}"
    final colonIndex = anime.id.indexOf(':');
    final extensionId =
        colonIndex != -1 ? anime.id.substring(0, colonIndex) : '';
    final animeId =
        colonIndex != -1 ? anime.id.substring(colonIndex + 1) : anime.id;

    return GestureDetector(
      onTap: () {
        if (extensionId.isNotEmpty) {
          context.push(
            '/anime/${Uri.encodeComponent(extensionId)}/${Uri.encodeComponent(animeId)}',
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover image
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  anime.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: anime.coverUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: NijiColors.surfaceVariant,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: NijiColors.surfaceVariant,
                            child: const Icon(Icons.movie_rounded, size: 32),
                          ),
                        )
                      : Container(
                          color: NijiColors.surfaceVariant,
                          child: const Icon(Icons.movie_rounded, size: 32),
                        ),
                  // Status badge in top-right
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _shortStatus(library.status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Title
          Text(
            anime.title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          // Episode count or progress
          if (anime.episodeCount != null)
            Text(
              '${library.progress}/${anime.episodeCount} ep',
              style: theme.textTheme.labelSmall?.copyWith(
                color: NijiColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  String _shortStatus(String status) {
    return switch (status) {
      LibraryStatus.watching => 'Watching',
      LibraryStatus.planToWatch => 'PTW',
      LibraryStatus.completed => 'Done',
      LibraryStatus.onHold => 'Hold',
      LibraryStatus.dropped => 'Drop',
      _ => status,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════
// Empty state
// ═══════════════════════════════════════════════════════════════════

class _EmptyLibraryView extends StatelessWidget {
  const _EmptyLibraryView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Your library is empty',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add to Library" on any anime to\nstart tracking your watchlist.',
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

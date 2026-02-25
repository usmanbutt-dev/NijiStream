/// NijiStream — Home screen.
///
/// Displays:
/// - A "Continue Watching" horizontal carousel from the user's watching list
/// - A "Recently Added" section showing the last few library items
/// - A welcome/empty state when the library has no items yet
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';
import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _continueWatchingProvider = StreamProvider<List<LibraryItem>>((ref) {
  return ref.watch(databaseProvider).watchContinueWatching(limit: 15);
});

final _recentLibraryProvider = StreamProvider<List<LibraryItem>>((ref) {
  return ref.watch(databaseProvider).watchLibrary();
});

// ═══════════════════════════════════════════════════════════════════
// Home Screen
// ═══════════════════════════════════════════════════════════════════

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final continueAsync = ref.watch(_continueWatchingProvider);
    final recentAsync = ref.watch(_recentLibraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'Niji',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Stream',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(context, theme, continueAsync, recentAsync),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    AsyncValue<List<LibraryItem>> continueAsync,
    AsyncValue<List<LibraryItem>> recentAsync,
  ) {
    if (continueAsync.isLoading && recentAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final continueItems = continueAsync.valueOrNull ?? [];
    final recentItems = recentAsync.valueOrNull ?? [];

    if (continueItems.isEmpty && recentItems.isEmpty) {
      return _WelcomeView(theme: theme);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Continue Watching ──
        if (continueItems.isNotEmpty) ...[
          _SectionHeader(title: 'Continue Watching', theme: theme),
          SizedBox(
            height: 200,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: continueItems.length,
              itemBuilder: (context, index) =>
                  _ContinueCard(item: continueItems[index]),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ── Recently Added ──
        if (recentItems.isNotEmpty) ...[
          _SectionHeader(title: 'Recently Added', theme: theme),
          ...recentItems.take(8).map((item) => _RecentListTile(item: item)),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Section Header
// ═══════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Continue Watching Card (horizontal carousel)
// ═══════════════════════════════════════════════════════════════════

class _ContinueCard extends StatelessWidget {
  final LibraryItem item;

  const _ContinueCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anime = item.anime;
    final library = item.library;
    final colonIndex = anime.id.indexOf(':');
    final extensionId =
        colonIndex != -1 ? anime.id.substring(0, colonIndex) : '';
    final animeId =
        colonIndex != -1 ? anime.id.substring(colonIndex + 1) : anime.id;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () {
          if (extensionId.isNotEmpty) {
            context.push(
              '/anime/${Uri.encodeComponent(extensionId)}/${Uri.encodeComponent(animeId)}',
            );
          }
        },
        child: SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
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

                      // Gradient overlay
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.7),
                              ],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                      ),

                      const Center(
                        child: Icon(
                          Icons.play_circle_rounded,
                          size: 36,
                          color: Colors.white70,
                        ),
                      ),

                      if (anime.episodeCount != null)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Text(
                            'Ep ${library.progress}/${anime.episodeCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black)
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                anime.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Recently Added List Tile
// ═══════════════════════════════════════════════════════════════════

class _RecentListTile extends StatelessWidget {
  final LibraryItem item;

  const _RecentListTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anime = item.anime;
    final library = item.library;
    final colonIndex = anime.id.indexOf(':');
    final extensionId =
        colonIndex != -1 ? anime.id.substring(0, colonIndex) : '';
    final animeId =
        colonIndex != -1 ? anime.id.substring(colonIndex + 1) : anime.id;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 60,
          child: anime.coverUrl != null
              ? CachedNetworkImage(
                  imageUrl: anime.coverUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: NijiColors.surfaceVariant),
                  errorWidget: (context, url, error) =>
                      Container(color: NijiColors.surfaceVariant),
                )
              : Container(
                  color: NijiColors.surfaceVariant,
                  child: const Icon(Icons.movie_rounded, size: 20),
                ),
        ),
      ),
      title: Text(anime.title, style: theme.textTheme.titleSmall),
      subtitle: Text(
        LibraryStatus.label(library.status),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
        ),
      ),
      trailing: anime.episodeCount != null
          ? Text(
              '${library.progress}/${anime.episodeCount} ep',
              style: theme.textTheme.labelSmall?.copyWith(
                color: NijiColors.textTertiary,
              ),
            )
          : null,
      onTap: () {
        if (extensionId.isNotEmpty) {
          context.push(
            '/anime/${Uri.encodeComponent(extensionId)}/${Uri.encodeComponent(animeId)}',
          );
        }
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Welcome / Empty State
// ═══════════════════════════════════════════════════════════════════

class _WelcomeView extends StatelessWidget {
  final ThemeData theme;
  const _WelcomeView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              AppConstants.appTagline,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Install extensions from Settings,\nthen search and add anime to your library.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: NijiColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

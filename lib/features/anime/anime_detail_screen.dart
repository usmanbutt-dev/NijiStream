/// NijiStream — Anime Detail screen.
///
/// Displays full anime information from an extension's `getDetail()`:
/// cover, synopsis, genres, and episode list. Supports adding the anime
/// to the user's library with a status selector.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/library_repository.dart';
import '../../extensions/api/extension_api.dart';
import '../../extensions/models/extension_manifest.dart';
import '../player/video_player_screen.dart';
import '../../data/services/download_service.dart';

class AnimeDetailScreen extends ConsumerStatefulWidget {
  final String extensionId;
  final String animeId;

  const AnimeDetailScreen({
    super.key,
    required this.extensionId,
    required this.animeId,
  });

  @override
  ConsumerState<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends ConsumerState<AnimeDetailScreen> {
  ExtensionAnimeDetail? _detail;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(extensionRepositoryProvider);
      final detail = await repo.getDetail(widget.extensionId, widget.animeId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _showLibrarySheet(UserLibraryTableData? currentEntry) {
    final detail = _detail;
    if (detail == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: NijiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LibrarySheet(
        currentStatus: currentEntry?.status,
        onStatusSelected: (status) async {
          Navigator.pop(ctx);
          final libraryRepo = ref.read(libraryRepositoryProvider);
          await libraryRepo.addToLibrary(
            extensionId: widget.extensionId,
            animeId: widget.animeId,
            detail: detail,
            status: status,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added to ${LibraryStatus.label(status)}'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        onRemove: currentEntry != null
            ? () async {
                Navigator.pop(ctx);
                await ref.read(libraryRepositoryProvider).removeFromLibrary(
                      extensionId: widget.extensionId,
                      animeId: widget.animeId,
                    );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Removed from library'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: NijiColors.error),
              const SizedBox(height: 16),
              Text('Failed to load details', style: theme.textTheme.titleMedium),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: NijiColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadDetail,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail!;

    // Reactively watch the library entry for this anime.
    final libraryEntry = ref.watch(
      _libraryEntryProvider(
        (extensionId: widget.extensionId, animeId: widget.animeId),
      ),
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero banner + cover + library button ──
          _DetailAppBar(
            detail: detail,
            theme: theme,
            libraryEntry: libraryEntry.value,
            onLibraryTap: () => _showLibrarySheet(libraryEntry.value),
          ),

          // ── Synopsis ──
          if (detail.synopsis != null && detail.synopsis!.isNotEmpty)
            SliverToBoxAdapter(
              child: _SynopsisSection(
                synopsis: detail.synopsis!,
                theme: theme,
              ),
            ),

          // ── Genres ──
          if (detail.genres.isNotEmpty)
            SliverToBoxAdapter(
              child: _GenresSection(genres: detail.genres, theme: theme),
            ),

          // ── Episode list header ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Episodes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${detail.episodes.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Episode list ──
          if (detail.episodes.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No episodes found',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: NijiColors.textSecondary,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final episode = detail.episodes[index];
                  return _EpisodeTile(
                    episode: episode,
                    extensionId: widget.extensionId,
                    theme: theme,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            extensionId: widget.extensionId,
                            episodeId: episode.id,
                            animeTitle: detail.title,
                            episodeNumber: episode.number,
                            episodeTitle: episode.title,
                            episodes: detail.episodes,
                            currentEpisodeIndex: index,
                          ),
                        ),
                      );
                    },
                  );
                },
                childCount: detail.episodes.length,
              ),
            ),

          // Bottom padding
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

// ── Library entry provider (scoped per anime) ─────────────────────────────

final _libraryEntryProvider = StreamProvider.family<UserLibraryTableData?,
    ({String extensionId, String animeId})>((ref, args) {
  return ref.read(libraryRepositoryProvider).watchEntry(
        extensionId: args.extensionId,
        animeId: args.animeId,
      );
});

// ═══════════════════════════════════════════════════════════════════
// Library Bottom Sheet
// ═══════════════════════════════════════════════════════════════════

class _LibrarySheet extends StatelessWidget {
  final String? currentStatus;
  final ValueChanged<String> onStatusSelected;
  final VoidCallback? onRemove;

  const _LibrarySheet({
    required this.currentStatus,
    required this.onStatusSelected,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Add to Library',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...LibraryStatus.all.map((status) => ListTile(
                  leading: Icon(
                    currentStatus == status
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: currentStatus == status
                        ? theme.colorScheme.primary
                        : NijiColors.textSecondary,
                  ),
                  title: Text(LibraryStatus.label(status)),
                  onTap: () => onStatusSelected(status),
                )),
            if (onRemove != null) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: NijiColors.error,
                ),
                title: const Text(
                  'Remove from Library',
                  style: TextStyle(color: NijiColors.error),
                ),
                onTap: onRemove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Detail App Bar (cover + title + library button)
// ═══════════════════════════════════════════════════════════════════

class _DetailAppBar extends StatelessWidget {
  final ExtensionAnimeDetail detail;
  final ThemeData theme;
  final UserLibraryTableData? libraryEntry;
  final VoidCallback onLibraryTap;

  const _DetailAppBar({
    required this.detail,
    required this.theme,
    required this.libraryEntry,
    required this.onLibraryTap,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background cover (darkened)
            if (detail.coverUrl != null)
              CachedNetworkImage(
                imageUrl: detail.coverUrl!,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.5),
                colorBlendMode: BlendMode.darken,
              ),

            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    NijiColors.background.withValues(alpha: 0.7),
                    NijiColors.background,
                  ],
                  stops: const [0.0, 0.7, 1.0],
                ),
              ),
            ),

            // Content: cover + title + library button
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Cover thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      height: 140,
                      child: detail.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: detail.coverUrl!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: NijiColors.surfaceVariant,
                              child: const Icon(Icons.movie_rounded, size: 40),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Title + status + library button
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          detail.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (detail.status != null) ...[
                          const SizedBox(height: 4),
                          _StatusChip(status: detail.status!),
                        ],
                        const SizedBox(height: 12),
                        _LibraryButton(
                          entry: libraryEntry,
                          onTap: onLibraryTap,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryButton extends StatelessWidget {
  final UserLibraryTableData? entry;
  final VoidCallback onTap;

  const _LibraryButton({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inLibrary = entry != null;

    if (inLibrary) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.bookmark_rounded, size: 16),
        label: Text(
          LibraryStatus.label(entry!.status),
          style: const TextStyle(fontSize: 12),
        ),
        onPressed: onTap,
      );
    }

    return FilledButton.icon(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
      label: const Text('Add to Library', style: TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isAiring = status.toLowerCase() == 'airing';
    final color = isAiring ? NijiColors.success : NijiColors.info;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Synopsis
// ═══════════════════════════════════════════════════════════════════

class _SynopsisSection extends StatefulWidget {
  final String synopsis;
  final ThemeData theme;

  const _SynopsisSection({required this.synopsis, required this.theme});

  @override
  State<_SynopsisSection> createState() => _SynopsisSectionState();
}

class _SynopsisSectionState extends State<_SynopsisSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Synopsis',
            style: widget.theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.synopsis,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: widget.theme.textTheme.bodyMedium?.copyWith(
              color: NijiColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (widget.synopsis.length > 150)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _expanded ? 'Show less' : 'Show more',
                  style: widget.theme.textTheme.labelMedium?.copyWith(
                    color: widget.theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Genres
// ═══════════════════════════════════════════════════════════════════

class _GenresSection extends StatelessWidget {
  final List<String> genres;
  final ThemeData theme;

  const _GenresSection({required this.genres, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: genres
            .map(
              (genre) => Chip(
                label: Text(genre),
                labelStyle: theme.textTheme.labelSmall,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            )
            .toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Episode Tile
// ═══════════════════════════════════════════════════════════════════

class _EpisodeTile extends ConsumerWidget {
  final ExtensionEpisode episode;
  final String extensionId;
  final ThemeData theme;
  final VoidCallback onTap;

  const _EpisodeTile({
    required this.episode,
    required this.extensionId,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: NijiColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${episode.number}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
      title: Text(
        episode.title ?? 'Episode ${episode.number}',
        style: theme.textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Download button — enqueues the episode URL
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 20),
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
            tooltip: 'Download',
            onPressed: () {
              ref.read(downloadServiceProvider).enqueue(
                    episodeId: '$extensionId:${episode.id}',
                    url: episode.url,
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Added to download queue'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          Icon(
            Icons.play_circle_outline_rounded,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

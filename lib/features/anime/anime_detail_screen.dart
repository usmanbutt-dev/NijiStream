/// NijiStream — Anime Detail screen.
///
/// Displays full anime information from an extension's `getDetail()`:
/// cover, synopsis, genres, and episode list. This is the entry point
/// for watching episodes once the video player is integrated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/colors.dart';
import '../../extensions/api/extension_api.dart';
import '../../extensions/models/extension_manifest.dart';

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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero banner + cover ──
          _DetailAppBar(detail: detail, theme: theme),

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
                    theme: theme,
                    onTap: () {
                      // TODO: Navigate to video player (Sprint 4)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Player coming soon — Episode ${episode.number}',
                          ),
                          behavior: SnackBarBehavior.floating,
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

// ═══════════════════════════════════════════════════════════════════
// Detail App Bar (cover + title hero)
// ═══════════════════════════════════════════════════════════════════

class _DetailAppBar extends StatelessWidget {
  final ExtensionAnimeDetail detail;
  final ThemeData theme;

  const _DetailAppBar({required this.detail, required this.theme});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background cover (blurred)
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

            // Content row: cover + title
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

                  // Title + status
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

class _EpisodeTile extends StatelessWidget {
  final ExtensionEpisode episode;
  final ThemeData theme;
  final VoidCallback onTap;

  const _EpisodeTile({
    required this.episode,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
      trailing: Icon(
        Icons.play_circle_outline_rounded,
        color: theme.colorScheme.primary.withValues(alpha: 0.7),
      ),
      onTap: onTap,
    );
  }
}

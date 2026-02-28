/// NijiStream — Anime Detail screen.
///
/// Displays full anime information from an extension's `getDetail()`:
/// cover, synopsis, genres, and episode list. Supports adding the anime
/// to the user's library with a status selector.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/hls_utils.dart';
import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/services/download_service.dart';
import '../../data/services/tracking_sync_service.dart';
import '../../extensions/api/extension_api.dart';
import '../../extensions/models/extension_manifest.dart';
import '../../extensions/repository/extension_repository.dart';
import '../player/video_player_screen.dart';

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

  /// Effective extension/anime IDs — may differ from widget params when a
  /// tracking-imported anime is resolved to a real extension.
  late String _effectiveExtensionId = widget.extensionId;
  late String _effectiveAnimeId = widget.animeId;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  /// Whether the widget's extensionId is a tracking source (not a real extension).
  bool get _isTrackingSource {
    const trackingSources = {'_tracking', 'anilist', 'mal'};
    return trackingSources.contains(widget.extensionId);
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(extensionRepositoryProvider);

      // If this is a tracking-imported anime, search installed extensions
      // for a match so we can show episodes and enable streaming.
      if (_isTrackingSource || !repo.isLoaded(widget.extensionId)) {
        final resolved = await _resolveViaExtensionSearch(repo);
        if (resolved) return; // _detail was set inside
      }

      final detail = await repo.getDetail(
          _effectiveExtensionId, _effectiveAnimeId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userFriendlyError(e);
          _isLoading = false;
        });
      }
    }
  }

  /// Search all loaded extensions for this anime's title.
  /// If a match is found, load the detail from that extension.
  /// Returns true if a match was found and _detail was set.
  Future<bool> _resolveViaExtensionSearch(ExtensionRepository repo) async {
    // Get the anime title from the local DB
    final db = ref.read(databaseProvider);
    final dbId = '${widget.extensionId}:${widget.animeId}';
    final anime = await db.getAnimeById(dbId);
    if (anime == null) return false;

    // Search all loaded extensions for this title
    final searchResults = await repo.searchAll(anime.title, 1);

    // Find the best match across all extensions
    final normalizedTitle = anime.title.toLowerCase().trim();
    for (final entry in searchResults.entries) {
      for (final result in entry.value.results) {
        if (result.title.toLowerCase().trim() == normalizedTitle) {
          // Exact title match — load detail from this extension
          _effectiveExtensionId = entry.key;
          _effectiveAnimeId = result.id;
          final detail =
              await repo.getDetail(_effectiveExtensionId, _effectiveAnimeId);
          if (mounted && detail != null) {
            // Also update the anime record in DB so future opens skip the search
            await db.upsertAnime(AnimeTableCompanion(
              id: Value(dbId),
              extensionId: Value(anime.extensionId),
              title: Value(anime.title),
              coverUrl: Value(detail.coverUrl ?? anime.coverUrl),
              bannerUrl: Value(detail.bannerUrl ?? anime.bannerUrl),
              synopsis: Value(detail.synopsis ?? anime.synopsis),
              anilistId: Value(anime.anilistId),
              malId: Value(anime.malId),
              updatedAt: Value(
                  DateTime.now().millisecondsSinceEpoch ~/ 1000),
            ));
            setState(() {
              _detail = detail;
              _isLoading = false;
            });
            return true;
          }
        }
      }
    }

    // No exact match — try partial match (contains)
    for (final entry in searchResults.entries) {
      if (entry.value.results.isNotEmpty) {
        // Use the first result from the first extension that returned results
        final result = entry.value.results.first;
        _effectiveExtensionId = entry.key;
        _effectiveAnimeId = result.id;
        final detail =
            await repo.getDetail(_effectiveExtensionId, _effectiveAnimeId);
        if (mounted && detail != null) {
          setState(() {
            _detail = detail;
            _isLoading = false;
          });
          return true;
        }
      }
    }

    // No extensions matched — show cached data from DB
    if (mounted) {
      final genres = anime.genres != null
          ? (jsonDecode(anime.genres!) as List<dynamic>)
              .cast<String>()
          : <String>[];
      setState(() {
        _detail = ExtensionAnimeDetail(
          title: anime.title,
          coverUrl: anime.coverUrl,
          bannerUrl: anime.bannerUrl,
          synopsis: anime.synopsis,
          genres: genres,
          status: anime.status,
        );
        _isLoading = false;
      });
    }
    return true;
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
          // Push status change to connected trackers (AniList/MAL)
          ref.read(trackingSyncProvider.notifier).onStatusChanged(
                extensionId: widget.extensionId,
                animeId: widget.animeId,
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
                // Push removal to connected trackers before deleting locally
                ref.read(trackingSyncProvider.notifier).onRemovedFromLibrary(
                      extensionId: widget.extensionId,
                      animeId: widget.animeId,
                    );
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
                  final metadataOnly = _isMetadataOnlyEpisodeId(episode.id);
                  return _EpisodeTile(
                    episode: episode,
                    extensionId: _effectiveExtensionId,
                    animeTitle: detail.title,
                    coverUrl: detail.coverUrl,
                    theme: theme,
                    isMetadataOnly: metadataOnly,
                    onTap: () {
                      // Metadata-only extensions produce stub episode IDs
                      // (e.g. "mal:21:ep:1", "anilist:12345:ep:1") that have
                      // no real stream. Show a snackbar instead of opening the
                      // player, which would just show "No video sources".
                      if (_isMetadataOnlyEpisodeId(episode.id)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'This source is metadata-only — no video stream available.',
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 3),
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            extensionId: _effectiveExtensionId,
                            animeId: _effectiveAnimeId,
                            episodeId: episode.id,
                            animeTitle: detail.title,
                            episodeNumber: episode.number,
                            episodeTitle: episode.title,
                            episodes: detail.episodes,
                            currentEpisodeIndex: index,
                            animeDetail: detail,
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

// ── Helpers ───────────────────────────────────────────────────────────────

/// Returns true if the episode ID is a synthetic stub from a metadata-only
/// extension (e.g. "mal:21:ep:1" from Jikan, "anilist:12345:ep:1" from AniList).
/// These episodes have no real video stream and should not open the player.
bool _isMetadataOnlyEpisodeId(String id) {
  return id.startsWith('mal:') || id.startsWith('anilist:');
}

// ── Download task provider (scoped per episode) ──────────────────────────

final _downloadTaskProvider =
    StreamProvider.family<DownloadTasksTableData?, String>((ref, episodeId) {
  return ref.watch(databaseProvider).watchDownloadTaskByEpisodeId(episodeId);
});

// ── Library entry provider (scoped per anime) ─────────────────────────────

final _libraryEntryProvider = StreamProvider.family<UserLibraryTableData?,
    ({String extensionId, String animeId})>((ref, args) {
  return ref.watch(libraryRepositoryProvider).watchEntry(
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
              (genre) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: theme.chipTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  genre,
                  style: theme.textTheme.labelSmall,
                ),
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

class _EpisodeTile extends ConsumerStatefulWidget {
  final ExtensionEpisode episode;
  final String extensionId;
  final String animeTitle;
  final String? coverUrl;
  final ThemeData theme;
  final VoidCallback onTap;
  final bool isMetadataOnly;

  const _EpisodeTile({
    required this.episode,
    required this.extensionId,
    required this.animeTitle,
    this.coverUrl,
    required this.theme,
    required this.onTap,
    required this.isMetadataOnly,
  });

  @override
  ConsumerState<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends ConsumerState<_EpisodeTile> {
  bool _enqueuing = false;

  String get _compositeEpisodeId =>
      '${widget.extensionId}:${widget.episode.id}';

  Future<void> _download() async {
    if (_enqueuing) return;
    setState(() => _enqueuing = true);

    try {
      // Resolve the actual stream URL via the extension before downloading.
      final repo = ref.read(extensionRepositoryProvider);
      final rawResponse = await repo.getVideoSources(
        widget.extensionId,
        widget.episode.id,
      );

      if (!mounted) return;

      if (rawResponse == null || rawResponse.sources.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No downloadable source found'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Expand HLS master playlist into quality variants.
      final response = await expandHlsVariants(rawResponse);
      if (!mounted) return;

      // If multiple sources, let user pick quality; otherwise download directly.
      ExtensionVideoSource source;
      if (response.sources.length > 1) {
        final picked = await _showDownloadQualityPicker(response.sources);
        if (picked == null || !mounted) return; // user cancelled
        source = picked;
      } else {
        source = response.sources.first;
      }

      final error = await ref.read(downloadServiceProvider).enqueue(
            episodeId: _compositeEpisodeId,
            url: source.url,
            headers: source.headers,
            animeTitle: widget.animeTitle,
            episodeNumber: widget.episode.number,
            coverUrl: widget.coverUrl,
            subtitles: response.subtitles,
          );

      if (!mounted) return;

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${source.quality}...'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFriendlyError(e)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enqueuing = false);
    }
  }

  /// Shows a bottom sheet letting the user pick download quality.
  /// Returns the selected source, or null if cancelled.
  Future<ExtensionVideoSource?> _showDownloadQualityPicker(
    List<ExtensionVideoSource> sources,
  ) async {
    return showModalBottomSheet<ExtensionVideoSource>(
      context: context,
      backgroundColor: NijiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Download Quality',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              ...sources.map(
                (source) => ListTile(
                  leading: Icon(
                    source.quality == 'auto'
                        ? Icons.auto_awesome_rounded
                        : Icons.hd_rounded,
                    color: NijiColors.textSecondary,
                  ),
                  title: Text(
                    source.quality == 'auto'
                        ? 'Auto (best quality)'
                        : source.quality,
                  ),
                  onTap: () => Navigator.pop(ctx, source),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch download state for this episode.
    final dlAsync = ref.watch(_downloadTaskProvider(_compositeEpisodeId));
    final dlTask = dlAsync.valueOrNull;
    final dlStatus = dlTask?.status;

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
            '${widget.episode.number}',
            style: widget.theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: widget.theme.colorScheme.primary,
            ),
          ),
        ),
      ),
      title: Text(
        widget.episode.title ?? 'Episode ${widget.episode.number}',
        style: widget.theme.textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        width: widget.isMetadataOnly ? 32 : 72,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Download button — hidden for metadata-only episodes
            if (!widget.isMetadataOnly) _buildDownloadIcon(dlStatus),
            Icon(
              widget.isMetadataOnly
                  ? Icons.info_outline_rounded
                  : Icons.play_circle_outline_rounded,
              size: 22,
              color: widget.isMetadataOnly
                  ? NijiColors.textTertiary
                  : widget.theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
      onTap: widget.onTap,
    );
  }

  Widget _buildDownloadIcon(String? dlStatus) {
    if (_enqueuing) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return switch (dlStatus) {
      DownloadStatus.completed => const Icon(
          Icons.download_done_rounded,
          size: 20,
          color: NijiColors.success,
        ),
      DownloadStatus.downloading => SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: null,
            color: widget.theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
        ),
      DownloadStatus.queued => Icon(
          Icons.schedule_rounded,
          size: 20,
          color: widget.theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      DownloadStatus.paused => const Icon(
          Icons.pause_circle_outline_rounded,
          size: 20,
          color: NijiColors.warning,
        ),
      DownloadStatus.failed => IconButton(
          icon: const Icon(Icons.error_outline_rounded, size: 20),
          color: NijiColors.error,
          tooltip: 'Download failed — tap to retry',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: _download,
        ),
      _ => IconButton(
          icon: const Icon(Icons.download_outlined, size: 20),
          color: widget.theme.colorScheme.primary.withValues(alpha: 0.7),
          tooltip: 'Download',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: _download,
        ),
    };
  }
}

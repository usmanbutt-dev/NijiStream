/// NijiStream — Downloads screen.
///
/// Two-level layout:
///  1. Grid of anime cards (grouped by anime title) — matches browse aesthetic.
///  2. Tap a card → episode list for that anime with status/progress/actions.
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';
import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';
import '../../data/services/download_service.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _downloadTasksProvider =
    StreamProvider<List<DownloadTasksTableData>>((ref) {
  return ref.watch(databaseProvider).watchDownloadTasks();
});

// ── Grouping model ───────────────────────────────────────────────────────────

/// A group of download tasks belonging to the same anime.
class _AnimeGroup {
  final String animeTitle;
  final String? coverUrl;
  final List<DownloadTasksTableData> episodes;

  _AnimeGroup({
    required this.animeTitle,
    required this.coverUrl,
    required this.episodes,
  });

  int get completedCount =>
      episodes.where((e) => e.status == DownloadStatus.completed).length;

  int get activeCount => episodes
      .where((e) =>
          e.status == DownloadStatus.downloading ||
          e.status == DownloadStatus.queued)
      .length;

  bool get hasFailures =>
      episodes.any((e) => e.status == DownloadStatus.failed);

  /// Summary line: "3 episodes" or "2 downloaded · 1 downloading"
  String get subtitle {
    final total = episodes.length;
    if (completedCount == total) return '$total episode${total > 1 ? 's' : ''}';
    final parts = <String>[];
    if (completedCount > 0) parts.add('$completedCount done');
    if (activeCount > 0) parts.add('$activeCount active');
    final failedCount =
        episodes.where((e) => e.status == DownloadStatus.failed).length;
    if (failedCount > 0) parts.add('$failedCount failed');
    final pausedCount =
        episodes.where((e) => e.status == DownloadStatus.paused).length;
    if (pausedCount > 0) parts.add('$pausedCount paused');
    return parts.join(' · ');
  }
}

List<_AnimeGroup> _groupByAnime(List<DownloadTasksTableData> tasks) {
  final map = <String, _AnimeGroup>{};
  for (final task in tasks) {
    final key = task.animeTitle ?? task.episodeId;
    if (map.containsKey(key)) {
      map[key]!.episodes.add(task);
    } else {
      map[key] = _AnimeGroup(
        animeTitle: key,
        coverUrl: task.coverUrl,
        episodes: [task],
      );
    }
  }
  // Sort episodes within each group by episode number.
  for (final group in map.values) {
    group.episodes.sort((a, b) =>
        (a.episodeNumber ?? 999).compareTo(b.episodeNumber ?? 999));
  }
  return map.values.toList();
}

// ═══════════════════════════════════════════════════════════════════
// Downloads Screen (Level 1 — Anime Grid)
// ═══════════════════════════════════════════════════════════════════

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(_downloadTasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          tasksAsync.whenOrNull(
                data: (tasks) => tasks.isNotEmpty
                    ? PopupMenuButton<_MenuAction>(
                        onSelected: (action) =>
                            _handleAction(ref, action, tasks),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _MenuAction.clearCompleted,
                            child: Text('Clear Completed'),
                          ),
                          const PopupMenuItem(
                            value: _MenuAction.clearFailed,
                            child: Text('Clear Failed'),
                          ),
                        ],
                      )
                    : null,
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: NijiColors.error)),
        ),
        data: (tasks) {
          if (tasks.isEmpty) return const _EmptyView();
          final groups = _groupByAnime(tasks);
          return _AnimeGrid(groups: groups);
        },
      ),
    );
  }

  void _handleAction(
    WidgetRef ref,
    _MenuAction action,
    List<DownloadTasksTableData> tasks,
  ) {
    final svc = ref.read(downloadServiceProvider);
    switch (action) {
      case _MenuAction.clearCompleted:
        for (final t
            in tasks.where((t) => t.status == DownloadStatus.completed)) {
          svc.cancel(t.id);
        }
      case _MenuAction.clearFailed:
        for (final t
            in tasks.where((t) => t.status == DownloadStatus.failed)) {
          svc.cancel(t.id);
        }
    }
  }
}

enum _MenuAction { clearCompleted, clearFailed }

// ═══════════════════════════════════════════════════════════════════
// Anime Grid (Level 1)
// ═══════════════════════════════════════════════════════════════════

class _AnimeGrid extends StatelessWidget {
  final List<_AnimeGroup> groups;

  const _AnimeGrid({required this.groups});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
          itemCount: groups.length,
          itemBuilder: (context, index) =>
              _AnimeCard(group: groups[index]),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Anime Card (one per anime)
// ═══════════════════════════════════════════════════════════════════

class _AnimeCard extends StatelessWidget {
  final _AnimeGroup group;

  const _AnimeCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActive = group.activeCount > 0;

    return InkWell(
      onTap: () => _openEpisodeList(context),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover with badge ──
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                color: NijiColors.surfaceVariant,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cover image
                    if (group.coverUrl != null)
                      CachedNetworkImage(
                        imageUrl: group.coverUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            _CoverPlaceholder(title: group.animeTitle),
                        errorWidget: (context, url, error) =>
                            _CoverPlaceholder(title: group.animeTitle),
                      )
                    else
                      _CoverPlaceholder(title: group.animeTitle),

                    // Episode count badge (bottom-left)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${group.episodes.length} ep',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    // Active download indicator (top-right)
                    if (hasActive)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: NijiColors.info.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'DL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (group.hasFailures)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: NijiColors.error.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'FAILED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Title ──
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
            child: Text(
              group.animeTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // ── Subtitle (episode count / status) ──
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2, top: 2),
            child: Text(
              group.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: NijiColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEpisodeList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DownloadedEpisodesScreen(group: group),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Downloaded Episodes Screen (Level 2 — matches browse detail layout)
// ═══════════════════════════════════════════════════════════════════

class _DownloadedEpisodesScreen extends ConsumerWidget {
  final _AnimeGroup group;

  const _DownloadedEpisodesScreen({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(_downloadTasksProvider);

    return Scaffold(
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allTasks) {
          final episodes = allTasks
              .where((t) => t.animeTitle == group.animeTitle)
              .toList()
            ..sort((a, b) =>
                (a.episodeNumber ?? 999).compareTo(b.episodeNumber ?? 999));

          if (episodes.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).pop();
            });
            return const SizedBox.shrink();
          }

          return CustomScrollView(
            slivers: [
              // ── Hero banner (same as anime detail screen) ──
              _DownloadDetailAppBar(
                title: group.animeTitle,
                coverUrl: group.coverUrl,
                episodeCount: episodes.length,
                theme: theme,
              ),

              // ── Episode list header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Downloaded Episodes',
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
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${episodes.length}',
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
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _EpisodeTile(task: episodes[index], theme: theme),
                  childCount: episodes.length,
                ),
              ),

              // Bottom padding
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Download Detail App Bar (hero banner — matches browse detail)
// ═══════════════════════════════════════════════════════════════════

class _DownloadDetailAppBar extends StatelessWidget {
  final String title;
  final String? coverUrl;
  final int episodeCount;
  final ThemeData theme;

  const _DownloadDetailAppBar({
    required this.title,
    required this.coverUrl,
    required this.episodeCount,
    required this.theme,
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
            if (coverUrl != null)
              CachedNetworkImage(
                imageUrl: coverUrl!,
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

            // Content: cover thumbnail + title + episode count
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
                      child: coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: coverUrl!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: NijiColors.surfaceVariant,
                              child: const Icon(
                                Icons.download_rounded,
                                size: 40,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Title + info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: NijiColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$episodeCount episode${episodeCount > 1 ? 's' : ''} downloaded',
                            style: const TextStyle(
                              color: NijiColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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

// ═══════════════════════════════════════════════════════════════════
// Episode Tile (inside Level 2 — matches browse episode tile style)
// ═══════════════════════════════════════════════════════════════════

class _EpisodeTile extends ConsumerWidget {
  final DownloadTasksTableData task;
  final ThemeData theme;

  const _EpisodeTile({required this.task, required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      // Episode number box (same style as browse screen)
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: NijiColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: task.episodeNumber != null
              ? Text(
                  '${task.episodeNumber}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                )
              : Icon(Icons.download_rounded,
                  color: theme.colorScheme.primary, size: 20),
        ),
      ),
      title: Text(
        task.episodeNumber != null
            ? 'Episode ${task.episodeNumber}'
            : task.episodeId,
        style: theme.textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _buildSubtitle(),
      trailing: _buildTrailing(context, ref),
      onTap: () {
        if (task.status == DownloadStatus.completed) {
          _playDownloaded(context);
        }
      },
    );
  }

  Widget? _buildSubtitle() {
    // Show progress bar for active downloads, file size for completed
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.paused) {
      final progressFraction = task.totalBytes > 0
          ? task.downloadedBytes / task.totalBytes
          : task.progress.clamp(0.0, 1.0);
      final statusColor = _statusColor(task.status);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progressFraction,
            backgroundColor: NijiColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(statusColor),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 4),
          Text(
            task.totalBytes > 0
                ? '${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)}'
                : '${(progressFraction * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: NijiColors.textTertiary,
            ),
          ),
        ],
      );
    }
    if (task.status == DownloadStatus.completed && task.totalBytes > 0) {
      return Text(
        _formatBytes(task.totalBytes),
        style: theme.textTheme.labelSmall?.copyWith(
          color: NijiColors.textTertiary,
        ),
      );
    }
    if (task.status == DownloadStatus.failed) {
      return Text(
        'Download failed',
        style: theme.textTheme.labelSmall?.copyWith(
          color: NijiColors.error,
        ),
      );
    }
    return null;
  }

  /// Trailing action icons — play/pause/resume/retry + remove.
  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    final svc = ref.read(downloadServiceProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary action based on status
        if (task.status == DownloadStatus.completed)
          Icon(
            Icons.play_circle_outline_rounded,
            size: 22,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          )
        else if (task.status == DownloadStatus.downloading)
          IconButton(
            icon: const Icon(Icons.pause_rounded, size: 20),
            color: NijiColors.warning,
            tooltip: 'Pause',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => svc.pause(task.id),
          )
        else if (task.status == DownloadStatus.paused)
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            color: NijiColors.info,
            tooltip: 'Resume',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => svc.resume(task.id),
          )
        else if (task.status == DownloadStatus.failed)
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: NijiColors.warning,
            tooltip: 'Retry',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => svc.resume(task.id),
          )
        else
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
        const SizedBox(width: 8),
        // Remove/cancel button
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 18),
          color: NijiColors.textTertiary,
          tooltip:
              task.status == DownloadStatus.completed ? 'Remove' : 'Cancel',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => svc.cancel(task.id),
        ),
      ],
    );
  }

  void _playDownloaded(BuildContext context) {
    final file = File(task.filePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File not found — it may have been moved or deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _OfflinePlayerScreen(
          filePath: task.filePath,
          title: _displayTitle(task),
        ),
      ),
    );
  }

  String _displayTitle(DownloadTasksTableData task) {
    if (task.animeTitle != null && task.episodeNumber != null) {
      return '${task.animeTitle} — Ep ${task.episodeNumber}';
    }
    if (task.animeTitle != null) return task.animeTitle!;
    final id = task.episodeId;
    final colonIdx = id.indexOf(':');
    return colonIdx != -1 ? id.substring(colonIdx + 1) : id;
  }

  static Color _statusColor(String status) => switch (status) {
        DownloadStatus.downloading => NijiColors.info,
        DownloadStatus.completed => NijiColors.success,
        DownloadStatus.failed => NijiColors.error,
        DownloadStatus.paused => NijiColors.warning,
        _ => NijiColors.textSecondary,
      };

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

// ═══════════════════════════════════════════════════════════════════
// Cover Placeholder
// ═══════════════════════════════════════════════════════════════════

class _CoverPlaceholder extends StatelessWidget {
  final String title;

  const _CoverPlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NijiColors.surfaceVariant,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: NijiColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════════════════════

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done_rounded,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No downloads yet',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Downloaded episodes will appear here\nfor offline viewing.',
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

// ═══════════════════════════════════════════════════════════════════
// Offline Player (plays downloaded local files)
// ═══════════════════════════════════════════════════════════════════

class _OfflinePlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const _OfflinePlayerScreen({required this.filePath, required this.title});

  @override
  State<_OfflinePlayerScreen> createState() => _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends State<_OfflinePlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  List<File> _subtitleFiles = [];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.filePath));
    _loadSubtitles();
  }

  /// Scans for subtitle files alongside the video (e.g. baseName.english.vtt).
  Future<void> _loadSubtitles() async {
    final videoFile = File(widget.filePath);
    final dir = videoFile.parent;
    final baseName = widget.filePath
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '');

    try {
      final files = await dir.list().toList();
      _subtitleFiles = files
          .whereType<File>()
          .where((f) {
            final name = f.path.split(Platform.pathSeparator).last;
            return name.startsWith(baseName) &&
                (name.endsWith('.vtt') || name.endsWith('.srt'));
          })
          .toList();

      if (_subtitleFiles.isNotEmpty) {
        // Auto-select first subtitle (prefer English).
        final english = _subtitleFiles.where(
            (f) => f.path.toLowerCase().contains('english'));
        final autoSub = english.isNotEmpty ? english.first : _subtitleFiles.first;
        final label = _subtitleLabel(autoSub);
        _player.setSubtitleTrack(
          SubtitleTrack.uri(autoSub.path, title: label, language: label),
        );
        if (mounted) setState(() {});
      }
    } catch (_) {
      // Non-fatal — play without subtitles.
    }
  }

  /// Extract a display label from a subtitle filename (e.g. "english" from "ep1.english.vtt").
  String _subtitleLabel(File f) {
    final name = f.path.split(Platform.pathSeparator).last;
    final parts = name.split('.');
    // Pattern: baseName.lang.ext — lang is second-to-last.
    if (parts.length >= 3) {
      return parts[parts.length - 2]
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
          .join(' ');
    }
    return 'Subtitle';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        actions: [
          if (_subtitleFiles.isNotEmpty)
            PopupMenuButton<File?>(
              icon: const Icon(Icons.subtitles_rounded),
              tooltip: 'Subtitles',
              onSelected: (file) {
                if (file == null) {
                  _player.setSubtitleTrack(SubtitleTrack.no());
                } else {
                  final label = _subtitleLabel(file);
                  _player.setSubtitleTrack(
                    SubtitleTrack.uri(file.path, title: label, language: label),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<File?>(
                  value: null,
                  child: Text('Off'),
                ),
                ..._subtitleFiles.map(
                  (f) => PopupMenuItem<File?>(
                    value: f,
                    child: Text(_subtitleLabel(f)),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Center(
        child: Video(controller: _controller),
      ),
    );
  }
}

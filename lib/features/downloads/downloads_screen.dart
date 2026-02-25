/// NijiStream — Downloads screen.
///
/// Shows all download tasks stored in the drift database.
/// Tasks can be in states: queued, downloading, paused, completed, failed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

// ═══════════════════════════════════════════════════════════════════
// Downloads Screen
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
                        onSelected: (action) => _handleAction(context, ref, action, tasks),
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
          return _DownloadList(tasks: tasks);
        },
      ),
    );
  }

  void _handleAction(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
    List<DownloadTasksTableData> tasks,
  ) {
    final svc = ref.read(downloadServiceProvider);
    switch (action) {
      case _MenuAction.clearCompleted:
        for (final t in tasks.where((t) => t.status == DownloadStatus.completed)) {
          svc.cancel(t.id);
        }
      case _MenuAction.clearFailed:
        for (final t in tasks.where((t) => t.status == DownloadStatus.failed)) {
          svc.cancel(t.id);
        }
    }
  }
}

enum _MenuAction { clearCompleted, clearFailed }

// ═══════════════════════════════════════════════════════════════════
// Download List
// ═══════════════════════════════════════════════════════════════════

class _DownloadList extends StatelessWidget {
  final List<DownloadTasksTableData> tasks;

  const _DownloadList({required this.tasks});

  @override
  Widget build(BuildContext context) {
    // Group by status for display order: downloading → queued → paused → completed → failed
    final ordered = [
      ...tasks.where((t) => t.status == DownloadStatus.downloading),
      ...tasks.where((t) => t.status == DownloadStatus.queued),
      ...tasks.where((t) => t.status == DownloadStatus.paused),
      ...tasks.where((t) => t.status == DownloadStatus.completed),
      ...tasks.where((t) => t.status == DownloadStatus.failed),
    ];

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: ordered.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _DownloadTile(task: ordered[index]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Download Tile
// ═══════════════════════════════════════════════════════════════════

class _DownloadTile extends ConsumerWidget {
  final DownloadTasksTableData task;

  const _DownloadTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(task.status);
    final statusIcon = _statusIcon(task.status);
    final progressFraction = task.totalBytes > 0
        ? task.downloadedBytes / task.totalBytes
        : task.progress.clamp(0.0, 1.0);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(statusIcon, color: statusColor, size: 20),
      ),
      title: Text(
        _displayTitle(task),
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.paused)
            LinearProgressIndicator(
              value: progressFraction,
              backgroundColor: NijiColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(statusColor),
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              _StatusChip(status: task.status, color: statusColor),
              const SizedBox(width: 8),
              if (task.totalBytes > 0)
                Text(
                  '${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: NijiColors.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
      trailing: _trailingActions(context, ref),
      isThreeLine: true,
    );
  }

  Widget _trailingActions(BuildContext context, WidgetRef ref) {
    final svc = ref.read(downloadServiceProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pause / Resume toggle
        if (task.status == DownloadStatus.downloading)
          IconButton(
            icon: const Icon(Icons.pause_rounded, size: 20),
            color: NijiColors.warning,
            tooltip: 'Pause',
            onPressed: () => svc.pause(task.id),
          )
        else if (task.status == DownloadStatus.paused)
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            color: NijiColors.info,
            tooltip: 'Resume',
            onPressed: () => svc.resume(task.id),
          )
        else if (task.status == DownloadStatus.failed)
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: NijiColors.warning,
            tooltip: 'Retry',
            onPressed: () => svc.resume(task.id),
          ),
        // Cancel / Delete
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          color: NijiColors.textTertiary,
          tooltip: task.status == DownloadStatus.completed ? 'Remove' : 'Cancel',
          onPressed: () => svc.cancel(task.id),
        ),
      ],
    );
  }

  Color _statusColor(String status) => switch (status) {
        DownloadStatus.downloading => NijiColors.info,
        DownloadStatus.completed => NijiColors.success,
        DownloadStatus.failed => NijiColors.error,
        DownloadStatus.paused => NijiColors.warning,
        _ => NijiColors.textSecondary,
      };

  IconData _statusIcon(String status) => switch (status) {
        DownloadStatus.downloading => Icons.downloading_rounded,
        DownloadStatus.completed => Icons.check_circle_rounded,
        DownloadStatus.failed => Icons.error_rounded,
        DownloadStatus.paused => Icons.pause_circle_rounded,
        _ => Icons.schedule_rounded,
      };

  /// Build a human-readable title for the download tile.
  String _displayTitle(DownloadTasksTableData task) {
    if (task.animeTitle != null && task.episodeNumber != null) {
      return '${task.animeTitle} — Ep ${task.episodeNumber}';
    }
    if (task.animeTitle != null) return task.animeTitle!;
    // Fallback: strip the extension prefix from the composite episodeId
    final id = task.episodeId;
    final colonIdx = id.indexOf(':');
    return colonIdx != -1 ? id.substring(colonIdx + 1) : id;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

// ── Status chip ──

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _label(String s) => switch (s) {
        DownloadStatus.downloading => 'Downloading',
        DownloadStatus.completed => 'Done',
        DownloadStatus.failed => 'Failed',
        DownloadStatus.paused => 'Paused',
        _ => 'Queued',
      };
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

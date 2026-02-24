/// NijiStream — Download service.
///
/// Manages a queue of episode downloads using Dio with progress tracking.
/// Each download task is persisted in the drift database so it survives
/// app restarts. The worker runs up to [maxConcurrent] downloads in parallel.
///
/// Usage:
/// ```dart
/// ref.read(downloadServiceProvider).enqueue(
///   episodeId: 'ext:ep-url',
///   url: 'https://cdn.example.com/ep1.mp4',
/// );
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';

// ── Provider ───────────────────────────────────────────────────────────────

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final service = DownloadService(ref.read(databaseProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

// ── Service ────────────────────────────────────────────────────────────────

class DownloadService {
  final AppDatabase _db;
  final _dio = Dio();
  final _activeTokens = <int, CancelToken>{};
  int _runningCount = 0;

  DownloadService(this._db);

  void dispose() {
    for (final token in _activeTokens.values) {
      token.cancel('App disposed');
    }
    _activeTokens.clear();
  }

  // ── Public API ──────────────────────────────────────────────────

  /// Add an episode to the download queue.
  ///
  /// If the episode is already queued/downloading, this is a no-op.
  Future<void> enqueue({
    required String episodeId,
    required String url,
    Map<String, String>? headers,
  }) async {
    // Check for existing task
    final existing = await (_db.select(_db.downloadTasksTable)
          ..where((t) => t.episodeId.equals(episodeId)))
        .getSingleOrNull();

    if (existing != null &&
        existing.status != DownloadStatus.failed &&
        existing.status != DownloadStatus.completed) {
      return; // already queued or in progress
    }

    final dir = await _downloadDir();
    final fileName = _safeFilename(episodeId, url);
    final filePath = p.join(dir.path, fileName);

    if (existing != null) {
      // Re-queue a previously failed/completed task
      await (_db.update(_db.downloadTasksTable)
            ..where((t) => t.id.equals(existing.id)))
          .write(DownloadTasksTableCompanion(
        url: Value(url),
        filePath: Value(filePath),
        status: const Value(DownloadStatus.queued),
        progress: const Value(0.0),
        downloadedBytes: const Value(0),
        totalBytes: const Value(0),
      ));
    } else {
      await _db.into(_db.downloadTasksTable).insert(
            DownloadTasksTableCompanion(
              episodeId: Value(episodeId),
              url: Value(url),
              filePath: Value(filePath),
              status: const Value(DownloadStatus.queued),
            ),
          );
    }

    _processQueue();
  }

  /// Pause a running download.
  Future<void> pause(int taskId) async {
    _activeTokens[taskId]?.cancel('Paused by user');
    _activeTokens.remove(taskId);
    await _setStatus(taskId, DownloadStatus.paused);
  }

  /// Resume a paused download.
  Future<void> resume(int taskId) async {
    final task = await (_db.select(_db.downloadTasksTable)
          ..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    if (task == null || task.status != DownloadStatus.paused) return;

    await _setStatus(taskId, DownloadStatus.queued);
    _processQueue();
  }

  /// Cancel and remove a download task.
  Future<void> cancel(int taskId) async {
    _activeTokens[taskId]?.cancel('Cancelled by user');
    _activeTokens.remove(taskId);
    final task = await (_db.select(_db.downloadTasksTable)
          ..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    if (task != null) {
      // Delete partial file
      final file = File(task.filePath);
      if (await file.exists()) await file.delete();
    }
    await _db.deleteDownloadTask(taskId);
  }

  // ── Queue processing ────────────────────────────────────────────

  Future<void> _processQueue() async {
    if (_runningCount >= AppConstants.defaultConcurrentDownloads) return;

    final queued = await (_db.select(_db.downloadTasksTable)
          ..where((t) => t.status.equals(DownloadStatus.queued))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(AppConstants.defaultConcurrentDownloads - _runningCount))
        .get();

    for (final task in queued) {
      _runningCount++;
      unawaited(_downloadTask(task));
    }
  }

  Future<void> _downloadTask(DownloadTasksTableData task) async {
    final cancelToken = CancelToken();
    _activeTokens[task.id] = cancelToken;

    await _setStatus(task.id, DownloadStatus.downloading);

    try {
      final dir = await _downloadDir();
      final file = File(task.filePath.isNotEmpty
          ? task.filePath
          : p.join(dir.path, _safeFilename(task.episodeId, task.url)));

      await _dio.download(
        task.url,
        file.path,
        cancelToken: cancelToken,
        deleteOnError: false,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          _updateProgress(task.id, received, total);
        },
      );

      await (_db.update(_db.downloadTasksTable)
            ..where((t) => t.id.equals(task.id)))
          .write(DownloadTasksTableCompanion(
        status: const Value(DownloadStatus.completed),
        progress: const Value(1.0),
      ));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // Paused or cancelled — status already updated by pause()/cancel()
      } else {
        await _setStatus(task.id, DownloadStatus.failed);
      }
    } catch (_) {
      await _setStatus(task.id, DownloadStatus.failed);
    } finally {
      _activeTokens.remove(task.id);
      _runningCount = (_runningCount - 1).clamp(0, 99);
      // Keep draining the queue
      _processQueue();
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────

  Future<void> _setStatus(int id, String status) async {
    await (_db.update(_db.downloadTasksTable)
          ..where((t) => t.id.equals(id)))
        .write(DownloadTasksTableCompanion(status: Value(status)));
  }

  void _updateProgress(int id, int received, int total) {
    // Fire-and-forget — no await to avoid blocking the download stream
    (_db.update(_db.downloadTasksTable)
          ..where((t) => t.id.equals(id)))
        .write(DownloadTasksTableCompanion(
      downloadedBytes: Value(received),
      totalBytes: Value(total),
      progress: Value(received / total),
    ));
  }

  Future<Directory> _downloadDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'NijiStream', 'downloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Build a safe filename from the episode id and URL.
  String _safeFilename(String episodeId, String url) {
    final ext = p.extension(Uri.parse(url).path);
    final safe = episodeId.replaceAll(RegExp(r'[^\w]'), '_');
    return '${safe.substring(0, safe.length.clamp(0, 80))}${ext.isEmpty ? '.mp4' : ext}';
  }
}

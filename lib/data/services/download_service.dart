/// NijiStream — Download service.
///
/// Manages a queue of episode downloads using Dio with progress tracking.
/// Each download task is persisted in the drift database so it survives
/// app restarts. The worker runs up to [maxConcurrent] downloads in parallel.
///
/// HLS (.m3u8) streams are handled by a pure Dart downloader that parses
/// the manifest and concatenates .ts segments — no ffmpeg required.
/// If ffmpeg is available on the system, it is used as a fallback for
/// better container format (.mp4 output).
///
/// Usage:
/// ```dart
/// ref.read(downloadServiceProvider).enqueue(
///   episodeId: 'ext:ep-url',
///   url: 'https://cdn.example.com/ep1.mp4',
///   animeTitle: 'One Piece',
///   episodeNumber: 1,
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

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../extensions/models/extension_manifest.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'ffmpeg_service.dart';
import 'hls_downloader.dart';

// ── Provider ───────────────────────────────────────────────────────────────

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final service = DownloadService(
    ref.read(databaseProvider),
    ref.read(ffmpegServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

// ── Service ────────────────────────────────────────────────────────────────

class DownloadService {
  final AppDatabase _db;
  final FfmpegService _ffmpeg;
  final _dio = Dio();
  final _activeTokens = <int, CancelToken>{};
  final _taskHeaders = <int, Map<String, String>>{};
  final _taskSubtitles = <int, List<ExtensionSubtitle>>{};
  int _runningCount = 0;

  DownloadService(this._db, this._ffmpeg);

  void dispose() {
    for (final token in _activeTokens.values) {
      token.cancel('App disposed');
    }
    _activeTokens.clear();
  }

  // ── Public API ──────────────────────────────────────────────────

  /// Add an episode to the download queue.
  ///
  /// Returns `null` on success, or a user-friendly error string on failure.
  /// If the episode is already queued/downloading, this is a no-op (returns null).
  Future<String?> enqueue({
    required String episodeId,
    required String url,
    Map<String, String>? headers,
    String? animeTitle,
    int? episodeNumber,
    String? coverUrl,
    List<ExtensionSubtitle>? subtitles,
  }) async {
    // Check for existing task
    final existing = await (_db.select(_db.downloadTasksTable)
          ..where((t) => t.episodeId.equals(episodeId)))
        .getSingleOrNull();

    if (existing != null &&
        existing.status != DownloadStatus.failed &&
        existing.status != DownloadStatus.completed) {
      return null; // already queued or in progress
    }

    final dir = await _downloadDir();
    final fileName = _safeFilename(episodeId, url);
    final filePath = p.join(dir.path, fileName);

    int taskId;
    if (existing != null) {
      taskId = existing.id;
      // Re-queue a previously failed/completed task
      await (_db.update(_db.downloadTasksTable)
            ..where((t) => t.id.equals(existing.id)))
          .write(DownloadTasksTableCompanion(
        url: Value(url),
        filePath: Value(filePath),
        coverUrl: Value(coverUrl),
        status: const Value(DownloadStatus.queued),
        progress: const Value(0.0),
        downloadedBytes: const Value(0),
        totalBytes: const Value(0),
      ));
    } else {
      taskId = await _db.into(_db.downloadTasksTable).insert(
            DownloadTasksTableCompanion(
              episodeId: Value(episodeId),
              animeTitle: Value(animeTitle),
              episodeNumber: Value(episodeNumber),
              coverUrl: Value(coverUrl),
              url: Value(url),
              filePath: Value(filePath),
              status: const Value(DownloadStatus.queued),
            ),
          );
    }

    // Store headers in-memory for HLS tasks that need them.
    if (headers != null && headers.isNotEmpty) {
      _taskHeaders[taskId] = headers;
    }

    // Store subtitles in-memory for downloading after the video completes.
    if (subtitles != null && subtitles.isNotEmpty) {
      _taskSubtitles[taskId] = subtitles;
    }

    _processQueue();
    return null; // success
  }

  /// Returns true if [url] is an HLS manifest.
  bool _isHlsUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('application/x-mpegurl');
  }

  /// Pause a running download.
  Future<void> pause(int taskId) async {
    _activeTokens[taskId]?.cancel('Paused by user');
    _activeTokens.remove(taskId);
    _ffmpeg.killTask(taskId);
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
    _ffmpeg.killTask(taskId);
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
      if (_isHlsUrl(task.url)) {
        unawaited(_downloadHlsTask(task));
      } else {
        unawaited(_downloadTask(task));
      }
    }
  }

  /// Direct file download (MP4, etc.).
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

      // Download subtitles alongside the video.
      await _downloadSubtitles(task.id, file.path);

      await (_db.update(_db.downloadTasksTable)
            ..where((t) => t.id.equals(task.id)))
          .write(const DownloadTasksTableCompanion(
        status: Value(DownloadStatus.completed),
        progress: Value(1.0),
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
      _processQueue();
    }
  }

  /// HLS download — pure Dart (primary) with ffmpeg fallback.
  Future<void> _downloadHlsTask(DownloadTasksTableData task) async {
    final cancelToken = CancelToken();
    _activeTokens[task.id] = cancelToken;

    await _setStatus(task.id, DownloadStatus.downloading);

    try {
      final dir = await _downloadDir();
      final safe = task.episodeId.replaceAll(RegExp(r'[^\w]'), '_');
      final baseName = safe.substring(0, safe.length.clamp(0, 80));
      final headers = _taskHeaders.remove(task.id);

      // Pure Dart HLS downloader first — handles headers reliably.
      final dartOutputPath = p.join(dir.path, '$baseName.ts');

      final dartSuccess = await downloadHlsStream(
        m3u8Url: task.url,
        outputPath: dartOutputPath,
        dio: _dio,
        headers: headers,
        cancelToken: cancelToken,
        onProgress: (downloaded, total) {
          _updateProgress(task.id, downloaded, total);
        },
      );

      if (dartSuccess) {
        await _downloadSubtitles(task.id, dartOutputPath);
        await (_db.update(_db.downloadTasksTable)
              ..where((t) => t.id.equals(task.id)))
            .write(DownloadTasksTableCompanion(
          filePath: Value(dartOutputPath),
          status: const Value(DownloadStatus.completed),
          progress: const Value(1.0),
        ));
        return;
      }

      if (cancelToken.isCancelled) return; // paused or cancelled

      // Dart downloader failed — try ffmpeg as fallback (better for
      // encrypted streams or edge cases, produces proper .mp4).
      if (await _ffmpeg.isAvailable()) {
        final ffmpegOutputPath = p.join(dir.path, '$baseName.mp4');
        final ffmpegSuccess = await _ffmpeg.downloadHls(
          m3u8Url: task.url,
          outputPath: ffmpegOutputPath,
          headers: headers,
          taskId: task.id,
        );

        if (ffmpegSuccess) {
          // Clean up partial .ts file from Dart attempt.
          final partial = File(dartOutputPath);
          if (await partial.exists()) await partial.delete();

          await _downloadSubtitles(task.id, ffmpegOutputPath);
          await (_db.update(_db.downloadTasksTable)
                ..where((t) => t.id.equals(task.id)))
              .write(DownloadTasksTableCompanion(
            filePath: Value(ffmpegOutputPath),
            status: const Value(DownloadStatus.completed),
            progress: const Value(1.0),
          ));
          return;
        }
      }

      await _setStatus(task.id, DownloadStatus.failed);
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) {
        await _setStatus(task.id, DownloadStatus.failed);
      }
    } catch (_) {
      await _setStatus(task.id, DownloadStatus.failed);
    } finally {
      _activeTokens.remove(task.id);
      _runningCount = (_runningCount - 1).clamp(0, 99);
      _processQueue();
    }
  }

  // ── Subtitle download ──────────────────────────────────────────

  /// Downloads VTT/SRT subtitle files alongside a completed video.
  ///
  /// Files are saved next to the video with a naming convention:
  /// `{baseName}.{lang}.vtt` — the offline player scans for these.
  Future<void> _downloadSubtitles(int taskId, String videoFilePath) async {
    final subtitles = _taskSubtitles.remove(taskId);
    if (subtitles == null || subtitles.isEmpty) return;

    final videoFile = File(videoFilePath);
    final dir = videoFile.parent.path;
    // Strip extension from video filename to get base name.
    final baseName = p.basenameWithoutExtension(videoFilePath);

    final usedNames = <String>{};
    for (final sub in subtitles) {
      try {
        // Sanitize language label for filename.
        var safeLang = sub.lang
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '_')
            .toLowerCase();
        final ext = sub.type == 'srt' ? 'srt' : 'vtt';

        // Deduplicate: if two subs share the same lang (e.g. two "Spanish"
        // variants), append an index to avoid overwriting.
        final key = '$safeLang.$ext';
        if (usedNames.contains(key)) {
          var i = 2;
          while (usedNames.contains('${safeLang}_$i.$ext')) {
            i++;
          }
          safeLang = '${safeLang}_$i';
        }
        usedNames.add('$safeLang.$ext');

        final subPath = p.join(dir, '$baseName.$safeLang.$ext');

        await _dio.download(sub.url, subPath);
        debugPrint('[DL] Subtitle downloaded: $subPath');
      } catch (e) {
        // Non-fatal — video still plays without subtitles.
        debugPrint('[DL] Subtitle download failed (${sub.lang}): $e');
      }
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
    final ext = _isHlsUrl(url) ? '.ts' : p.extension(Uri.parse(url).path);
    final safe = episodeId.replaceAll(RegExp(r'[^\w]'), '_');
    return '${safe.substring(0, safe.length.clamp(0, 80))}${ext.isEmpty ? '.mp4' : ext}';
  }
}

/// NijiStream — FFmpeg service.
///
/// Platform-aware ffmpeg wrapper for HLS-to-MP4 downloads.
/// On desktop (Windows/Linux/macOS), delegates to a system-installed ffmpeg
/// binary via `Process.run`. On mobile, returns unavailable for now.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ffmpegServiceProvider = Provider<FfmpegService>((ref) {
  return FfmpegService();
});

class FfmpegService {
  bool? _available;

  /// Active ffmpeg processes keyed by download task ID.
  final _activeProcesses = <int, Process>{};

  /// Check whether ffmpeg is available on this platform.
  Future<bool> isAvailable() async {
    if (_available != null) return _available!;

    // Mobile platforms: not supported yet (would need ffmpeg_kit).
    if (Platform.isAndroid || Platform.isIOS) {
      _available = false;
      return false;
    }

    // Desktop: check if ffmpeg is on PATH.
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      _available = result.exitCode == 0;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  /// Download an HLS stream to an MP4 file.
  ///
  /// [m3u8Url] — The .m3u8 manifest URL.
  /// [outputPath] — Where to save the resulting .mp4 file.
  /// [headers] — Optional HTTP headers (e.g. Referer) needed to fetch segments.
  /// [onProgress] — Called with log lines for progress tracking.
  /// [taskId] — Optional download task ID for cancel support.
  ///
  /// Returns true on success, false on failure.
  Future<bool> downloadHls({
    required String m3u8Url,
    required String outputPath,
    Map<String, String>? headers,
    void Function(String line)? onProgress,
    int? taskId,
  }) async {
    if (!await isAvailable()) return false;

    // Build the header string. ffmpeg expects each header on its own line
    // terminated with \r\n. The entire block is a single -headers argument.
    // On Windows, we must avoid embedded newlines in the arg — use \r\n
    // as literal characters within the string, not actual line breaks.
    final args = <String>[
      '-y',
      if (headers != null && headers.isNotEmpty) ...[
        '-headers',
        headers.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\r\n'),
      ],
      '-i', m3u8Url,
      '-c', 'copy',
      '-bsf:a', 'aac_adtstoasc',
      outputPath,
    ];

    debugPrint('FFmpeg command: ffmpeg ${args.join(' ')}');

    try {
      final process = await Process.start('ffmpeg', args);

      // Store process handle for cancel support.
      if (taskId != null) {
        _activeProcesses[taskId] = process;
      }

      // ffmpeg writes progress to stderr.
      process.stderr.transform(const SystemEncoding().decoder).listen((line) {
        onProgress?.call(line);
      });

      final exitCode = await process.exitCode;

      if (taskId != null) _activeProcesses.remove(taskId);

      if (exitCode != 0) {
        debugPrint('FFmpeg exited with code $exitCode');
        return false;
      }
      return true;
    } catch (e) {
      if (taskId != null) _activeProcesses.remove(taskId);
      debugPrint('FFmpeg error: $e');
      return false;
    }
  }

  /// Kill the ffmpeg process for a given download task.
  void killTask(int taskId) {
    final process = _activeProcesses.remove(taskId);
    if (process != null) {
      debugPrint('FFmpeg: killing process for task $taskId');
      process.kill(ProcessSignal.sigterm);
    }
  }
}

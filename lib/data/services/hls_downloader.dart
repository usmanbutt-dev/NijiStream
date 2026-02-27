/// NijiStream — Pure Dart HLS downloader.
///
/// Downloads HLS (.m3u8) streams without requiring ffmpeg or any native
/// dependencies. Parses the manifest, downloads each .ts segment with Dio,
/// and concatenates them into a single file.
///
/// MPEG-TS segments are designed to be concatenated — the result plays
/// natively in media_kit / mpv / VLC.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Downloads an HLS stream to a local file.
///
/// [m3u8Url]    — The .m3u8 manifest URL.
/// [outputPath] — Destination file path (typically .ts).
/// [headers]    — Optional HTTP headers (Referer, etc.).
/// [cancelToken] — Dio cancel token for pause/cancel support.
/// [onProgress] — Called with (downloadedSegments, totalSegments).
///
/// Returns `true` on success, `false` on failure.
Future<bool> downloadHlsStream({
  required String m3u8Url,
  required String outputPath,
  required Dio dio,
  Map<String, String>? headers,
  CancelToken? cancelToken,
  void Function(int downloaded, int total)? onProgress,
}) async {
  try {
    final segmentUrls = await _resolveSegmentUrls(dio, m3u8Url, headers);
    if (segmentUrls.isEmpty) {
      debugPrint('[HLS] No segments found in manifest: $m3u8Url');
      return false;
    }

    debugPrint('[HLS] Found ${segmentUrls.length} segments');

    final outFile = File(outputPath);
    final sink = outFile.openWrite(mode: FileMode.writeOnly);

    try {
      for (var i = 0; i < segmentUrls.length; i++) {
        if (cancelToken?.isCancelled == true) {
          return false;
        }

        final response = await dio.get<List<int>>(
          segmentUrls[i],
          options: Options(
            responseType: ResponseType.bytes,
            headers: headers != null ? Map<String, dynamic>.from(headers) : null,
          ),
          cancelToken: cancelToken,
        );

        if (response.data != null) {
          sink.add(response.data!);
        }

        onProgress?.call(i + 1, segmentUrls.length);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    debugPrint('[HLS] Download complete: $outputPath');
    return true;
  } on DioException catch (e) {
    if (CancelToken.isCancel(e)) {
      debugPrint('[HLS] Download cancelled');
      return false;
    }
    debugPrint('[HLS] Download error: $e');
    return false;
  } catch (e) {
    debugPrint('[HLS] Download error: $e');
    return false;
  }
}

/// Parses the .m3u8 manifest and returns a flat list of .ts segment URLs.
///
/// Handles both master playlists (selects highest bandwidth variant) and
/// media playlists (direct segment list).
Future<List<String>> _resolveSegmentUrls(
  Dio dio,
  String m3u8Url,
  Map<String, String>? headers,
) async {
  final content = await _fetchManifest(dio, m3u8Url, headers);
  if (content == null) return [];

  final lines = content.split('\n').map((l) => l.trim()).toList();

  // Encrypted segments (AES-128) can't be handled by simple concatenation.
  if (lines.any((l) => l.startsWith('#EXT-X-KEY') && !l.contains('METHOD=NONE'))) {
    debugPrint('[HLS] Encrypted stream detected (AES-128) — not supported by pure Dart downloader');
    return [];
  }

  // Check if this is a master playlist (contains #EXT-X-STREAM-INF).
  if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'))) {
    final variantUrl = _selectBestVariant(lines, m3u8Url);
    if (variantUrl == null) return [];
    // Recurse into the media playlist.
    return _resolveSegmentUrls(dio, variantUrl, headers);
  }

  // Media playlist — extract segment URLs.
  return _parseMediaPlaylist(lines, m3u8Url);
}

/// Fetches manifest text from a URL.
Future<String?> _fetchManifest(
  Dio dio,
  String url,
  Map<String, String>? headers,
) async {
  try {
    final response = await dio.get<String>(
      url,
      options: Options(
        headers: headers != null ? Map<String, dynamic>.from(headers) : null,
      ),
    );
    return response.data;
  } catch (e) {
    debugPrint('[HLS] Failed to fetch manifest: $e');
    return null;
  }
}

/// From a master playlist, select the variant with the highest bandwidth.
String? _selectBestVariant(List<String> lines, String masterUrl) {
  int bestBandwidth = -1;
  String? bestUrl;

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;

    // Parse BANDWIDTH from the tag.
    final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i]);
    final bandwidth = bwMatch != null ? int.tryParse(bwMatch.group(1)!) ?? 0 : 0;

    // The variant URL is on the next non-empty, non-comment line.
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].isEmpty || lines[j].startsWith('#')) continue;
      if (bandwidth > bestBandwidth) {
        bestBandwidth = bandwidth;
        bestUrl = _resolveUrl(lines[j], masterUrl);
      }
      break;
    }
  }

  return bestUrl;
}

/// Extract .ts segment URLs from a media playlist.
List<String> _parseMediaPlaylist(List<String> lines, String playlistUrl) {
  final segments = <String>[];

  for (final line in lines) {
    if (line.isEmpty || line.startsWith('#')) continue;
    segments.add(_resolveUrl(line, playlistUrl));
  }

  return segments;
}

/// Resolve a possibly-relative URL against a base URL.
String _resolveUrl(String url, String baseUrl) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = Uri.parse(baseUrl);
  return base.resolve(url).toString();
}

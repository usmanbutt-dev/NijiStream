/// NijiStream — HLS utility functions.
///
/// Parses master M3U8 playlists to extract individual quality variant URLs.
/// Used by both the video player (quality selector) and download flow.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../extensions/models/extension_manifest.dart';

/// Represents a quality variant parsed from an M3U8 master playlist.
class HlsVariant {
  final String url;
  final int height;
  final int bandwidth;

  const HlsVariant({
    required this.url,
    required this.height,
    required this.bandwidth,
  });

  String get quality => '${height}p';
}

/// Fetches a master M3U8 playlist and extracts quality variants.
///
/// Returns an empty list if the URL is not a master playlist, or if
/// fetching/parsing fails (graceful fallback).
Future<List<HlsVariant>> parseM3U8Variants(
  String masterUrl, {
  Map<String, String>? headers,
  Dio? dio,
}) async {
  try {
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

    final resp = await client.get<String>(
      masterUrl,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
      ),
    );

    final m3u8 = resp.data;
    if (m3u8 == null || !m3u8.contains('#EXT-X-STREAM-INF')) {
      return [];
    }

    final lastSlash = masterUrl.lastIndexOf('/');
    final baseUrl =
        lastSlash != -1 ? masterUrl.substring(0, lastSlash + 1) : masterUrl;

    final lines = m3u8.split('\n');
    final variants = <HlsVariant>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

      final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      final height =
          resMatch != null ? int.tryParse(resMatch.group(2)!) : null;
      if (height == null) continue;

      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final bandwidth =
          bwMatch != null ? int.tryParse(bwMatch.group(1)!) ?? 0 : 0;

      String? variantUrl;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isNotEmpty && !next.startsWith('#')) {
          variantUrl = next;
          break;
        }
      }
      if (variantUrl == null) continue;

      if (!variantUrl.startsWith('http')) {
        variantUrl = baseUrl + variantUrl;
      }

      variants.add(HlsVariant(
        url: variantUrl,
        height: height,
        bandwidth: bandwidth,
      ));
    }

    // Sort by quality descending (highest first).
    variants.sort((a, b) => b.height.compareTo(a.height));

    debugPrint('M3U8 variants found: ${variants.length}');
    return variants;
  } catch (e) {
    debugPrint('M3U8 variant parsing failed: $e');
    return [];
  }
}

/// Expands a single-source HLS video response into multiple quality sources.
///
/// If the response has a single HLS source whose URL is a master M3U8,
/// fetches and parses it to extract quality variants. Returns "auto"
/// (master playlist) + individual quality options.
Future<ExtensionVideoResponse> expandHlsVariants(
  ExtensionVideoResponse response,
) async {
  if (response.sources.length != 1) return response;
  final source = response.sources.first;
  if (source.type != 'hls') return response;

  final variants = await parseM3U8Variants(
    source.url,
    headers: source.headers,
  );

  if (variants.isEmpty) return response;

  final expandedSources = <ExtensionVideoSource>[
    source, // "auto" — the master playlist
    ...variants.map((v) => ExtensionVideoSource(
          url: v.url,
          quality: v.quality,
          type: 'hls',
          server: source.server,
          headers: source.headers,
        )),
  ];

  return ExtensionVideoResponse(
    sources: expandedSources,
    subtitles: response.subtitles,
  );
}

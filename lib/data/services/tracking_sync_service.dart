/// NijiStream — Tracking sync service.
///
/// Handles pulling anime lists from AniList/MAL into the local library,
/// pushing local changes (progress, status, removal) back to trackers,
/// and deduplicating anime that appear on both services.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';

// ── Constants ──────────────────────────────────────────────────────────────

const _secureStorage = FlutterSecureStorage();
const _kAnilistToken = 'niji_anilist_token';
const _kMalToken = 'niji_mal_token';

// ── Status mappings ────────────────────────────────────────────────────────

const _anilistToLocal = {
  'CURRENT': 'watching',
  'PLANNING': 'plan_to_watch',
  'COMPLETED': 'completed',
  'PAUSED': 'on_hold',
  'DROPPED': 'dropped',
  'REPEATING': 'watching',
};

const _localToAnilist = {
  'watching': 'CURRENT',
  'plan_to_watch': 'PLANNING',
  'completed': 'COMPLETED',
  'on_hold': 'PAUSED',
  'dropped': 'DROPPED',
};

const _malToLocal = {
  'watching': 'watching',
  'plan_to_watch': 'plan_to_watch',
  'completed': 'completed',
  'on_hold': 'on_hold',
  'dropped': 'dropped',
};

const _localToMal = {
  'watching': 'watching',
  'plan_to_watch': 'plan_to_watch',
  'completed': 'completed',
  'on_hold': 'on_hold',
  'dropped': 'dropped',
};

// ── Sync state ─────────────────────────────────────────────────────────────

class SyncStatus {
  final bool isSyncing;
  final String? lastResult;
  final DateTime? lastSyncTime;

  const SyncStatus({
    this.isSyncing = false,
    this.lastResult,
    this.lastSyncTime,
  });

  SyncStatus copyWith({
    bool? isSyncing,
    String? lastResult,
    DateTime? lastSyncTime,
  }) =>
      SyncStatus(
        isSyncing: isSyncing ?? this.isSyncing,
        lastResult: lastResult ?? this.lastResult,
        lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      );
}

// ── Service ────────────────────────────────────────────────────────────────

class TrackingSyncService extends StateNotifier<SyncStatus> {
  final AppDatabase _db;
  final _dio = Dio();

  TrackingSyncService(this._db) : super(const SyncStatus());

  // ── Pull: AniList ──────────────────────────────────────────────

  /// Pull the user's full anime list from AniList into the local library.
  /// Returns the number of entries imported/updated.
  Future<int> pullFromAnilist(String token) async {
    state = state.copyWith(isSyncing: true);
    try {
      // First get the user's ID
      final viewerResp = await _dio.post(
        ApiUrls.anilistGraphQL,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }),
        data: jsonEncode({'query': '{ Viewer { id } }'}),
      );
      final viewerData = viewerResp.data as Map<String, dynamic>;
      final viewerId = ((viewerData['data']
              as Map<String, dynamic>)['Viewer']
          as Map<String, dynamic>)['id'] as int;

      // Fetch the full anime list
      final listResp = await _dio.post(
        ApiUrls.anilistGraphQL,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }),
        data: jsonEncode({
          'query': '''
query (\$userId: Int) {
  MediaListCollection(userId: \$userId, type: ANIME) {
    lists {
      entries {
        id
        status
        progress
        score(format: POINT_10)
        media {
          id
          idMal
          title { romaji english }
          coverImage { large }
          episodes
          status
        }
      }
    }
  }
}''',
          'variables': {'userId': viewerId},
        }),
      );

      final listData = listResp.data as Map<String, dynamic>;
      final listDataInner = listData['data'] as Map<String, dynamic>?;
      final mediaListCollection =
          listDataInner?['MediaListCollection'] as Map<String, dynamic>?;
      final lists =
          (mediaListCollection?['lists'] as List<dynamic>?) ?? [];

      var count = 0;
      for (final list in lists) {
        final listMap = list as Map<String, dynamic>;
        final entries = (listMap['entries'] as List<dynamic>?) ?? [];
        for (final entry in entries) {
          await _importAnilistEntry(entry as Map<String, dynamic>);
          count++;
        }
      }

      state = state.copyWith(
        isSyncing: false,
        lastResult: 'Imported $count anime from AniList',
        lastSyncTime: DateTime.now(),
      );
      return count;
    } catch (e) {
      debugPrint('AniList pull error: $e');
      state = state.copyWith(
        isSyncing: false,
        lastResult: 'AniList sync failed: $e',
      );
      return 0;
    }
  }

  Future<void> _importAnilistEntry(Map<String, dynamic> entry) async {
    final media = entry['media'] as Map<String, dynamic>;
    final anilistId = (media['id'] as num).toInt();
    final malId = (media['idMal'] as num?)?.toInt();
    final title = media['title'] as Map<String, dynamic>;
    final displayTitle =
        (title['english'] as String?) ?? (title['romaji'] as String?) ?? '';
    final coverUrl =
        (media['coverImage'] as Map<String, dynamic>?)?['large'] as String?;
    final episodeCount = (media['episodes'] as num?)?.toInt();
    final mediaStatus = media['status'] as String?;

    final entryStatus = entry['status'] as String? ?? 'CURRENT';
    final progress = (entry['progress'] as num?)?.toInt() ?? 0;
    final score = (entry['score'] as num?)?.toDouble() ?? 0.0;

    final localStatus = _anilistToLocal[entryStatus] ?? 'watching';

    // Check if this anime already exists in the DB (by anilistId or malId)
    var existing = await _db.getAnimeByAnilistId(anilistId);
    existing ??= malId != null ? await _db.getAnimeByMalId(malId) : null;

    final animeId = existing?.id ?? 'anilist:$anilistId';

    // Upsert anime metadata
    await _db.upsertAnime(AnimeTableCompanion(
      id: Value(animeId),
      extensionId: const Value('_tracking'),
      title: Value(displayTitle),
      coverUrl: Value(coverUrl),
      status: Value(mediaStatus?.toLowerCase()),
      episodeCount: Value(episodeCount),
      anilistId: Value(anilistId),
      malId: Value(malId),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    ));

    // Upsert library entry
    await _db.upsertLibraryEntry(
      animeId: animeId,
      status: localStatus,
      progress: progress,
      score: score,
    );
  }

  // ── Pull: MAL ──────────────────────────────────────────────────

  /// Pull the user's full anime list from MAL into the local library.
  /// Returns the number of entries imported/updated.
  Future<int> pullFromMal(String token) async {
    state = state.copyWith(isSyncing: true);
    try {
      var count = 0;
      String? nextUrl =
          '${ApiUrls.malApi}/users/@me/animelist?fields=list_status,num_episodes,main_picture,alternative_titles&limit=100&nsfw=true';

      while (nextUrl != null) {
        final resp = await _dio.get(
          nextUrl,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        final data = resp.data as Map<String, dynamic>;
        final nodes = (data['data'] as List<dynamic>?) ?? [];

        for (final node in nodes) {
          await _importMalEntry(node as Map<String, dynamic>);
          count++;
        }

        // MAL uses paging with next URL
        final paging = data['paging'] as Map<String, dynamic>?;
        nextUrl = paging?['next'] as String?;
      }

      state = state.copyWith(
        isSyncing: false,
        lastResult: 'Imported $count anime from MAL',
        lastSyncTime: DateTime.now(),
      );
      return count;
    } catch (e) {
      debugPrint('MAL pull error: $e');
      state = state.copyWith(
        isSyncing: false,
        lastResult: 'MAL sync failed: $e',
      );
      return 0;
    }
  }

  Future<void> _importMalEntry(Map<String, dynamic> node) async {
    final animeNode = node['node'] as Map<String, dynamic>;
    final malId = (animeNode['id'] as num).toInt();
    final title = animeNode['title'] as String? ?? '';
    final mainPicture = animeNode['main_picture'] as Map<String, dynamic>?;
    final coverUrl = mainPicture?['large'] as String? ??
        mainPicture?['medium'] as String?;
    final episodeCount = (animeNode['num_episodes'] as num?)?.toInt();

    final listStatus = node['list_status'] as Map<String, dynamic>?;
    final malStatus = listStatus?['status'] as String? ?? 'watching';
    final progress =
        (listStatus?['num_episodes_watched'] as num?)?.toInt() ?? 0;
    final score = (listStatus?['score'] as num?)?.toDouble() ?? 0.0;

    final localStatus = _malToLocal[malStatus] ?? 'watching';

    // Dedup: check if this anime already exists by malId (e.g. from AniList pull)
    var existing = await _db.getAnimeByMalId(malId);

    if (existing != null) {
      // Anime already in DB (from AniList or prior MAL sync) — update tracking IDs
      await _db.upsertAnime(AnimeTableCompanion(
        id: Value(existing.id),
        extensionId: Value(existing.extensionId),
        title: Value(existing.title),
        coverUrl: Value(coverUrl ?? existing.coverUrl),
        malId: Value(malId),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ));

      // Don't overwrite library entry if it already exists — AniList data takes precedence
      final libEntry = await _db.getLibraryEntry(existing.id);
      if (libEntry == null) {
        await _db.upsertLibraryEntry(
          animeId: existing.id,
          status: localStatus,
          progress: progress,
          score: score,
        );
      }
      return;
    }

    // Try title-based dedup as fallback
    existing = await _findByNormalizedTitle(title);
    if (existing != null) {
      // Found by title — update malId on existing record
      await _db.upsertAnime(AnimeTableCompanion(
        id: Value(existing.id),
        extensionId: Value(existing.extensionId),
        title: Value(existing.title),
        malId: Value(malId),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ));

      final libEntry = await _db.getLibraryEntry(existing.id);
      if (libEntry == null) {
        await _db.upsertLibraryEntry(
          animeId: existing.id,
          status: localStatus,
          progress: progress,
          score: score,
        );
      }
      return;
    }

    // No existing record — create new
    final animeId = 'mal:$malId';
    await _db.upsertAnime(AnimeTableCompanion(
      id: Value(animeId),
      extensionId: const Value('_tracking'),
      title: Value(title),
      coverUrl: Value(coverUrl),
      episodeCount: Value(episodeCount),
      malId: Value(malId),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    ));

    await _db.upsertLibraryEntry(
      animeId: animeId,
      status: localStatus,
      progress: progress,
      score: score,
    );
  }

  /// Normalize a title for comparison: lowercase, strip non-alphanumeric.
  String _normalizeTitle(String title) {
    return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Try to find an existing anime by normalized title match.
  Future<AnimeTableData?> _findByNormalizedTitle(String title) async {
    final normalized = _normalizeTitle(title);
    if (normalized.isEmpty) return null;

    // Get all anime and compare normalized titles
    // This is O(n) but only runs during sync (not on every query)
    final allAnime = await _db.select(_db.animeTable).get();
    for (final anime in allAnime) {
      if (_normalizeTitle(anime.title) == normalized) return anime;
    }
    return null;
  }

  // ── Push: progress/status updates ──────────────────────────────

  /// Called when an episode is completed — pushes progress to all connected trackers.
  Future<void> onEpisodeCompleted({
    required String extensionId,
    required String animeId,
    required int episodeNumber,
  }) async {
    final dbAnimeId = '$extensionId:$animeId';
    final anime = await _db.getAnimeById(dbAnimeId);
    if (anime == null) return;

    final anilistToken = await _secureStorage.read(key: _kAnilistToken);
    final malToken = await _secureStorage.read(key: _kMalToken);

    if (anilistToken != null && anime.anilistId != null) {
      try {
        await _pushProgressToAnilist(
          token: anilistToken,
          anilistId: anime.anilistId!,
          progress: episodeNumber,
        );
      } catch (e) {
        debugPrint('Failed to push progress to AniList: $e');
        await _enqueue('anilist', dbAnimeId, 'update_progress',
            {'progress': episodeNumber});
      }
    }

    if (malToken != null && anime.malId != null) {
      try {
        await _pushProgressToMal(
          token: malToken,
          malId: anime.malId!,
          progress: episodeNumber,
        );
      } catch (e) {
        debugPrint('Failed to push progress to MAL: $e');
        await _enqueue(
            'mal', dbAnimeId, 'update_progress', {'progress': episodeNumber});
      }
    }
  }

  /// Called when the user changes an anime's status in the library sheet.
  Future<void> onStatusChanged({
    required String extensionId,
    required String animeId,
    required String status,
  }) async {
    final dbAnimeId = '$extensionId:$animeId';
    final anime = await _db.getAnimeById(dbAnimeId);
    if (anime == null) return;

    final anilistToken = await _secureStorage.read(key: _kAnilistToken);
    final malToken = await _secureStorage.read(key: _kMalToken);

    if (anilistToken != null && anime.anilistId != null) {
      try {
        await _pushStatusToAnilist(
          token: anilistToken,
          anilistId: anime.anilistId!,
          status: status,
        );
      } catch (e) {
        debugPrint('Failed to push status to AniList: $e');
        await _enqueue(
            'anilist', dbAnimeId, 'update_status', {'status': status});
      }
    }

    if (malToken != null && anime.malId != null) {
      try {
        await _pushStatusToMal(
          token: malToken,
          malId: anime.malId!,
          status: status,
        );
      } catch (e) {
        debugPrint('Failed to push status to MAL: $e');
        await _enqueue('mal', dbAnimeId, 'update_status', {'status': status});
      }
    }
  }

  /// Called when the user removes an anime from the library.
  Future<void> onRemovedFromLibrary({
    required String extensionId,
    required String animeId,
  }) async {
    final dbAnimeId = '$extensionId:$animeId';
    final anime = await _db.getAnimeById(dbAnimeId);
    if (anime == null) return;

    final anilistToken = await _secureStorage.read(key: _kAnilistToken);
    final malToken = await _secureStorage.read(key: _kMalToken);

    if (anilistToken != null && anime.anilistId != null) {
      try {
        await _pushRemoveToAnilist(
          token: anilistToken,
          anilistId: anime.anilistId!,
        );
      } catch (e) {
        debugPrint('Failed to push removal to AniList: $e');
        await _enqueue('anilist', dbAnimeId, 'remove', {});
      }
    }

    if (malToken != null && anime.malId != null) {
      try {
        await _pushRemoveToMal(
          token: malToken,
          malId: anime.malId!,
        );
      } catch (e) {
        debugPrint('Failed to push removal to MAL: $e');
        await _enqueue('mal', dbAnimeId, 'remove', {});
      }
    }
  }

  /// Full sync: pull from all connected services + process queue.
  Future<void> syncAll() async {
    final anilistToken = await _secureStorage.read(key: _kAnilistToken);
    final malToken = await _secureStorage.read(key: _kMalToken);

    if (anilistToken != null) await pullFromAnilist(anilistToken);
    if (malToken != null) await pullFromMal(malToken);
    await processQueue();
  }

  // ── AniList push helpers ───────────────────────────────────────

  Future<void> _pushProgressToAnilist({
    required String token,
    required int anilistId,
    required int progress,
  }) async {
    await _dio.post(
      ApiUrls.anilistGraphQL,
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }),
      data: jsonEncode({
        'query':
            'mutation (\$mediaId: Int, \$progress: Int) { SaveMediaListEntry(mediaId: \$mediaId, progress: \$progress) { id progress } }',
        'variables': {'mediaId': anilistId, 'progress': progress},
      }),
    );
  }

  Future<void> _pushStatusToAnilist({
    required String token,
    required int anilistId,
    required String status,
  }) async {
    final anilistStatus = _localToAnilist[status] ?? 'CURRENT';
    await _dio.post(
      ApiUrls.anilistGraphQL,
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }),
      data: jsonEncode({
        'query':
            'mutation (\$mediaId: Int, \$status: MediaListStatus) { SaveMediaListEntry(mediaId: \$mediaId, status: \$status) { id status } }',
        'variables': {'mediaId': anilistId, 'status': anilistStatus},
      }),
    );
  }

  Future<void> _pushRemoveToAnilist({
    required String token,
    required int anilistId,
  }) async {
    // First we need to find the media list entry ID
    final resp = await _dio.post(
      ApiUrls.anilistGraphQL,
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }),
      data: jsonEncode({
        'query':
            'query (\$mediaId: Int) { MediaList(mediaId: \$mediaId) { id } }',
        'variables': {'mediaId': anilistId},
      }),
    );
    final respData = resp.data as Map<String, dynamic>?;
    final dataMap = respData?['data'] as Map<String, dynamic>?;
    final mediaList = dataMap?['MediaList'] as Map<String, dynamic>?;
    final entryId = (mediaList?['id'] as num?)?.toInt();
    if (entryId == null) return;

    await _dio.post(
      ApiUrls.anilistGraphQL,
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }),
      data: jsonEncode({
        'query':
            'mutation (\$id: Int) { DeleteMediaListEntry(id: \$id) { deleted } }',
        'variables': {'id': entryId},
      }),
    );
  }

  // ── MAL push helpers ───────────────────────────────────────────

  Future<void> _pushProgressToMal({
    required String token,
    required int malId,
    required int progress,
  }) async {
    await _dio.patch(
      '${ApiUrls.malApi}/anime/$malId/my_list_status',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        contentType: Headers.formUrlEncodedContentType,
      ),
      data: {'num_watched_episodes': progress},
    );
  }

  Future<void> _pushStatusToMal({
    required String token,
    required int malId,
    required String status,
  }) async {
    final malStatus = _localToMal[status] ?? 'watching';
    await _dio.patch(
      '${ApiUrls.malApi}/anime/$malId/my_list_status',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        contentType: Headers.formUrlEncodedContentType,
      ),
      data: {'status': malStatus},
    );
  }

  Future<void> _pushRemoveToMal({
    required String token,
    required int malId,
  }) async {
    await _dio.delete(
      '${ApiUrls.malApi}/anime/$malId/my_list_status',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  // ── Offline queue ──────────────────────────────────────────────

  Future<void> _enqueue(
    String accountId,
    String animeId,
    String action,
    Map<String, dynamic> payload,
  ) async {
    await _db.insertSyncQueueItem(TrackingSyncQueueTableCompanion.insert(
      trackingAccountId: accountId,
      animeId: animeId,
      action: action,
      payload: jsonEncode(payload),
    ));
  }

  /// Process all pending queue items — retry failed pushes.
  Future<void> processQueue() async {
    // Clean up items that have exceeded max retries
    await _db.deleteExpiredSyncQueueItems();

    final items = await _db.getAllSyncQueueItems();
    for (final item in items) {
      try {
        final payload =
            jsonDecode(item.payload) as Map<String, dynamic>? ?? {};
        final anime = await _db.getAnimeById(item.animeId);
        if (anime == null) {
          await _db.deleteSyncQueueItem(item.id);
          continue;
        }

        String? token;
        if (item.trackingAccountId == 'anilist') {
          token = await _secureStorage.read(key: _kAnilistToken);
        } else if (item.trackingAccountId == 'mal') {
          token = await _secureStorage.read(key: _kMalToken);
        }
        if (token == null) {
          await _db.deleteSyncQueueItem(item.id);
          continue;
        }

        switch (item.action) {
          case 'update_progress':
            final progress = (payload['progress'] as num?)?.toInt() ?? 0;
            if (item.trackingAccountId == 'anilist' &&
                anime.anilistId != null) {
              await _pushProgressToAnilist(
                  token: token,
                  anilistId: anime.anilistId!,
                  progress: progress);
            } else if (item.trackingAccountId == 'mal' &&
                anime.malId != null) {
              await _pushProgressToMal(
                  token: token, malId: anime.malId!, progress: progress);
            }
          case 'update_status':
            final status = payload['status'] as String? ?? 'watching';
            if (item.trackingAccountId == 'anilist' &&
                anime.anilistId != null) {
              await _pushStatusToAnilist(
                  token: token, anilistId: anime.anilistId!, status: status);
            } else if (item.trackingAccountId == 'mal' &&
                anime.malId != null) {
              await _pushStatusToMal(
                  token: token, malId: anime.malId!, status: status);
            }
          case 'remove':
            if (item.trackingAccountId == 'anilist' &&
                anime.anilistId != null) {
              await _pushRemoveToAnilist(
                  token: token, anilistId: anime.anilistId!);
            } else if (item.trackingAccountId == 'mal' &&
                anime.malId != null) {
              await _pushRemoveToMal(token: token, malId: anime.malId!);
            }
        }

        // Success — remove from queue
        await _db.deleteSyncQueueItem(item.id);
      } catch (e) {
        debugPrint('Queue item ${item.id} failed: $e');
        await _db.incrementSyncQueueAttempts(item.id);
      }
    }
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final trackingSyncProvider =
    StateNotifierProvider<TrackingSyncService, SyncStatus>((ref) {
  return TrackingSyncService(ref.read(databaseProvider));
});

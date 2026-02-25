/// NijiStream — Library repository.
///
/// Coordinates adding/updating/removing anime from the user's library.
/// Writes to both [AnimeTable] (metadata) and [UserLibraryTable] (status).
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../../extensions/models/extension_manifest.dart';

class LibraryRepository {
  final AppDatabase _db;

  LibraryRepository(this._db);

  // ── Add / Update ──────────────────────────────────────────────────

  /// Add an anime to the library (or update its status if already present).
  ///
  /// [extensionId] and [animeId] together form the unique database key.
  /// [detail] supplies the metadata to cache in [AnimeTable].
  Future<void> addToLibrary({
    required String extensionId,
    required String animeId,
    required ExtensionAnimeDetail detail,
    required String status,
  }) async {
    final dbAnimeId = '$extensionId:$animeId';

    // Cache anime metadata so the library screen can display covers, titles, etc.
    await _db.upsertAnime(AnimeTableCompanion(
      id: Value(dbAnimeId),
      extensionId: Value(extensionId),
      title: Value(detail.title),
      coverUrl: Value(detail.coverUrl),
      bannerUrl: Value(detail.bannerUrl),
      synopsis: Value(detail.synopsis),
      status: Value(detail.status),
      genres: Value(
        detail.genres.isNotEmpty ? jsonEncode(detail.genres) : null,
      ),
      episodeCount: Value(
        detail.episodes.isNotEmpty ? detail.episodes.length : null,
      ),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    ));

    await _db.upsertLibraryEntry(animeId: dbAnimeId, status: status);
  }

  /// Auto-add anime to the library only if not already present.
  ///
  /// This is called when playback starts and should NEVER overwrite an existing
  /// entry (including its status). Use [addToLibrary] when the user explicitly
  /// selects a status via the library sheet.
  Future<void> autoAddIfAbsent({
    required String extensionId,
    required String animeId,
    required ExtensionAnimeDetail detail,
  }) async {
    final dbAnimeId = '$extensionId:$animeId';

    // Always keep the anime metadata up-to-date
    await _db.upsertAnime(AnimeTableCompanion(
      id: Value(dbAnimeId),
      extensionId: Value(extensionId),
      title: Value(detail.title),
      coverUrl: Value(detail.coverUrl),
      bannerUrl: Value(detail.bannerUrl),
      synopsis: Value(detail.synopsis),
      status: Value(detail.status),
      genres: Value(
        detail.genres.isNotEmpty ? jsonEncode(detail.genres) : null,
      ),
      episodeCount: Value(
        detail.episodes.isNotEmpty ? detail.episodes.length : null,
      ),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    ));

    // Only insert the library entry if it doesn't already exist.
    // This preserves any existing status (e.g. 'completed') set by the user.
    await _db.insertLibraryIfAbsent(
      animeId: dbAnimeId,
      status: 'watching',
    );
  }

  // ── Progress ──────────────────────────────────────────────────────

  /// Update the watched-episode counter, but only if [newProgress] is higher
  /// than the stored value (prevents rewatching from resetting progress).
  Future<void> setProgressIfGreater({
    required String extensionId,
    required String animeId,
    required int newProgress,
  }) =>
      _db.setProgressIfGreater('$extensionId:$animeId', newProgress);

  // ── Remove ────────────────────────────────────────────────────────

  /// Remove an anime from the library.
  Future<void> removeFromLibrary({
    required String extensionId,
    required String animeId,
  }) =>
      _db.removeFromLibrary('$extensionId:$animeId');

  // ── Read ──────────────────────────────────────────────────────────

  /// Watch the library entry for a specific anime (reactive stream).
  Stream<UserLibraryTableData?> watchEntry({
    required String extensionId,
    required String animeId,
  }) =>
      _db.watchLibraryEntry('$extensionId:$animeId');

  /// Watch all library items, optionally filtered by [status].
  Stream<List<LibraryItem>> watchLibrary({String? status}) =>
      _db.watchLibrary(status: status);
}

/// Riverpod provider for [LibraryRepository].
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.read(databaseProvider));
});

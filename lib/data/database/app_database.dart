/// NijiStream — drift database definition.
///
/// This is the central database class that drift uses for code generation.
/// It references all [Table] classes and will generate `app_database.g.dart`
/// containing the actual query implementations.
///
/// After any table changes, regenerate with:
/// ```
/// dart run build_runner build --delete-conflicting-outputs
/// ```
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'app_database.g.dart';

/// A joined row returned by [AppDatabase.watchLibrary].
class LibraryItem {
  final AnimeTableData anime;
  final UserLibraryTableData library;
  const LibraryItem({required this.anime, required this.library});
}

@DriftDatabase(
  tables: [
    AnimeTable,
    UserLibraryTable,
    WatchProgressTable,
    DownloadTasksTable,
    TrackingAccountsTable,
    TrackingSyncQueueTable,
    ExtensionsTable,
    ExtensionReposTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor that accepts a custom [QueryExecutor] — useful for testing
  /// with in-memory databases.
  AppDatabase.forTesting(super.executor);

  /// Bump this when you change the schema. drift will run the
  /// [migration] strategy to update existing databases.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        // Create all tables on first launch.
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // v1 → v2:
        //  - Drop the old `episodes` table (never populated; extensions provide
        //    episodes at runtime, not persistence).
        //  - Drop old `watch_progress` table that referenced `episodes` via FK.
        //  - Re-create `watch_progress` without the broken FK constraint.
        //  - Drop old `download_tasks` table (had broken FK on episodeId).
        //  - Re-create `download_tasks` without the FK constraint and with new
        //    `anime_title` + `episode_number` display columns.
        if (from < 2) {
          // Drop old tables that had broken FK references.
          // Using deleteTable(name) — safe even if table doesn't exist (IF EXISTS).
          await m.deleteTable('watch_progress');
          await m.deleteTable('download_tasks');
          await m.deleteTable('episodes');

          // Create updated tables with corrected schema.
          await m.createTable(watchProgressTable);
          await m.createTable(downloadTasksTable);
        }
        if (from < 3) {
          // Add cover_url column for the downloads grid redesign.
          await m.addColumn(downloadTasksTable, downloadTasksTable.coverUrl);
        }
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Anime helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Upsert (insert or replace) an anime record.
  Future<void> upsertAnime(AnimeTableCompanion row) =>
      into(animeTable).insertOnConflictUpdate(row);

  // ═══════════════════════════════════════════════════════════════════
  // Library helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Get the library entry for a specific anime, if it exists.
  Future<UserLibraryTableData?> getLibraryEntry(String animeId) =>
      (select(userLibraryTable)..where((t) => t.animeId.equals(animeId)))
          .getSingleOrNull();

  /// Watch the library entry for a specific anime (reactive stream).
  Stream<UserLibraryTableData?> watchLibraryEntry(String animeId) =>
      (select(userLibraryTable)..where((t) => t.animeId.equals(animeId)))
          .watchSingleOrNull();

  /// Insert or update a library entry for the given anime.
  /// If an entry already exists, only [status] and [updatedAt] are updated.
  /// Progress is NOT overwritten — use [setProgressIfGreater] for that.
  Future<void> upsertLibraryEntry({
    required String animeId,
    required String status,
    int progress = 0,
    double score = 0.0,
  }) async {
    final existing = await getLibraryEntry(animeId);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (existing != null) {
      // Do NOT overwrite status if user already has a deliberate status set.
      // Only update when caller explicitly changes it (e.g. library sheet).
      await (update(userLibraryTable)
            ..where((t) => t.animeId.equals(animeId)))
          .write(UserLibraryTableCompanion(
        status: Value(status),
        updatedAt: Value(now),
      ));
    } else {
      await into(userLibraryTable).insert(UserLibraryTableCompanion(
        animeId: Value(animeId),
        status: Value(status),
        progress: Value(progress),
        score: Value(score),
        updatedAt: Value(now),
      ));
    }
  }

  /// Add anime to library ONLY if not already present (used by auto-add on play).
  /// Respects existing status — never overwrites a user's deliberate status.
  Future<void> insertLibraryIfAbsent({
    required String animeId,
    required String status,
  }) async {
    final existing = await getLibraryEntry(animeId);
    if (existing != null) return; // Already in library — preserve existing entry
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await into(userLibraryTable).insert(UserLibraryTableCompanion(
      animeId: Value(animeId),
      status: Value(status),
      updatedAt: Value(now),
    ));
  }

  /// Increment the watched-episode counter for a library entry.
  ///
  /// Only increments if the new value is greater than the stored value,
  /// so re-watching an episode doesn't double-count.
  Future<void> setProgressIfGreater(String animeId, int newProgress) async {
    final existing = await getLibraryEntry(animeId);
    if (existing == null) return;
    if (newProgress <= existing.progress) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await (update(userLibraryTable)..where((t) => t.animeId.equals(animeId)))
        .write(UserLibraryTableCompanion(
      progress: Value(newProgress),
      updatedAt: Value(now),
    ));
  }

  /// Remove an anime from the library.
  Future<int> removeFromLibrary(String animeId) =>
      (delete(userLibraryTable)..where((t) => t.animeId.equals(animeId))).go();

  /// Watch the N most recently updated library items with status 'watching'.
  /// Used by the Home screen's "Continue Watching" row.
  Stream<List<LibraryItem>> watchContinueWatching({int limit = 10}) {
    final query = select(userLibraryTable).join([
      innerJoin(animeTable, animeTable.id.equalsExp(userLibraryTable.animeId)),
    ]);
    query.where(userLibraryTable.status.equals('watching'));
    query.orderBy([OrderingTerm.desc(userLibraryTable.updatedAt)]);
    query.limit(limit);

    return query.watch().map(
          (rows) => rows
              .map((row) => LibraryItem(
                    anime: row.readTable(animeTable),
                    library: row.readTable(userLibraryTable),
                  ))
              .toList(),
        );
  }

  /// Watch all library items joined with their anime data.
  /// Pass [status] to filter by a specific status, or null for all.
  Stream<List<LibraryItem>> watchLibrary({String? status}) {
    final query = select(userLibraryTable).join([
      innerJoin(animeTable, animeTable.id.equalsExp(userLibraryTable.animeId)),
    ]);

    if (status != null) {
      query.where(userLibraryTable.status.equals(status));
    }

    query.orderBy([OrderingTerm.desc(userLibraryTable.updatedAt)]);

    return query.watch().map(
          (rows) => rows
              .map((row) => LibraryItem(
                    anime: row.readTable(animeTable),
                    library: row.readTable(userLibraryTable),
                  ))
              .toList(),
        );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Watch progress helpers (SQLite-backed)
  // ═══════════════════════════════════════════════════════════════════

  /// Get the saved watch progress for a specific episode.
  Future<WatchProgressTableData?> getWatchProgress(
    String animeId,
    String episodeId,
  ) =>
      (select(watchProgressTable)
            ..where((t) => t.animeId.equals(animeId) & t.episodeId.equals(episodeId)))
          .getSingleOrNull();

  /// Save or update the watch progress for an episode.
  Future<void> upsertWatchProgress({
    required String animeId,
    required String episodeId,
    required int positionMs,
    required int durationMs,
    required bool completed,
  }) async {
    final existing = await getWatchProgress(animeId, episodeId);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (existing != null) {
      await (update(watchProgressTable)
            ..where((t) =>
                t.animeId.equals(animeId) & t.episodeId.equals(episodeId)))
          .write(WatchProgressTableCompanion(
        positionMs: Value(positionMs),
        durationMs: Value(durationMs),
        completed: Value(completed ? 1 : 0),
        updatedAt: Value(now),
      ));
    } else {
      await into(watchProgressTable).insert(WatchProgressTableCompanion(
        animeId: Value(animeId),
        episodeId: Value(episodeId),
        positionMs: Value(positionMs),
        durationMs: Value(durationMs),
        completed: Value(completed ? 1 : 0),
        updatedAt: Value(now),
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Anime lookup helpers (for tracking sync deduplication)
  // ═══════════════════════════════════════════════════════════════════

  /// Get an anime record by its primary key.
  Future<AnimeTableData?> getAnimeById(String id) =>
      (select(animeTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Find an anime by its AniList ID (for dedup when syncing MAL after AniList).
  Future<AnimeTableData?> getAnimeByAnilistId(int anilistId) =>
      (select(animeTable)..where((t) => t.anilistId.equals(anilistId)))
          .getSingleOrNull();

  /// Find an anime by its MAL ID (for dedup when syncing AniList after MAL).
  Future<AnimeTableData?> getAnimeByMalId(int malId) =>
      (select(animeTable)..where((t) => t.malId.equals(malId)))
          .getSingleOrNull();

  // ═══════════════════════════════════════════════════════════════════
  // Tracking sync queue helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Get all pending sync queue items ordered by creation time.
  Future<List<TrackingSyncQueueTableData>> getAllSyncQueueItems() =>
      (select(trackingSyncQueueTable)
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Insert a new sync queue item.
  Future<void> insertSyncQueueItem(
          TrackingSyncQueueTableCompanion companion) =>
      into(trackingSyncQueueTable).insert(companion);

  /// Delete a sync queue item by id (after successful push).
  Future<void> deleteSyncQueueItem(int id) =>
      (delete(trackingSyncQueueTable)..where((t) => t.id.equals(id))).go();

  /// Increment the attempt counter for a failed sync queue item.
  Future<void> incrementSyncQueueAttempts(int id) async {
    final item = await (select(trackingSyncQueueTable)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (item == null) return;
    await (update(trackingSyncQueueTable)..where((t) => t.id.equals(id)))
        .write(TrackingSyncQueueTableCompanion(
      attempts: Value(item.attempts + 1),
    ));
  }

  /// Delete sync queue items that have exceeded max retries.
  Future<void> deleteExpiredSyncQueueItems({int maxAttempts = 3}) =>
      (delete(trackingSyncQueueTable)
            ..where((t) => t.attempts.isBiggerOrEqualValue(maxAttempts)))
          .go();

  // ═══════════════════════════════════════════════════════════════════
  // Tracking account helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Upsert a tracking account (insert or replace by id).
  Future<void> upsertTrackingAccount(TrackingAccountsTableCompanion row) =>
      into(trackingAccountsTable).insertOnConflictUpdate(row);

  /// Delete a tracking account by service id (e.g. "anilist", "mal").
  Future<int> deleteTrackingAccount(String serviceId) =>
      (delete(trackingAccountsTable)
            ..where((t) => t.id.equals(serviceId)))
          .go();

  // ═══════════════════════════════════════════════════════════════════
  // Download helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Watch all download tasks ordered by creation time (newest first).
  Stream<List<DownloadTasksTableData>> watchDownloadTasks() {
    return (select(downloadTasksTable)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Watch a single download task by composite episode ID.
  Stream<DownloadTasksTableData?> watchDownloadTaskByEpisodeId(
      String episodeId) {
    return (select(downloadTasksTable)
          ..where((t) => t.episodeId.equals(episodeId)))
        .watchSingleOrNull();
  }

  /// Remove a download task by id.
  Future<int> deleteDownloadTask(int id) =>
      (delete(downloadTasksTable)..where((t) => t.id.equals(id))).go();

  // ═══════════════════════════════════════════════════════════════════
  // Bulk data management helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Delete all download tasks from the database.
  Future<int> deleteAllDownloadTasks() => delete(downloadTasksTable).go();

  /// Delete all anime and library entries imported from a specific tracking
  /// service (extensionId = '_tracking' and id starts with [prefix]).
  Future<void> deleteTrackingData(String service) async {
    // Tracking-imported anime have IDs like "anilist:123" or "mal:456",
    // and extensionId = '_tracking'.
    final prefix = '$service:';
    final imported = await (select(animeTable)
          ..where(
              (t) => t.extensionId.equals('_tracking') & t.id.like('$prefix%')))
        .get();
    for (final anime in imported) {
      await (delete(userLibraryTable)
            ..where((t) => t.animeId.equals(anime.id)))
          .go();
      await (delete(animeTable)..where((t) => t.id.equals(anime.id))).go();
    }
    // Also clear the sync queue for this service
    await (delete(trackingSyncQueueTable)
          ..where((t) => t.trackingAccountId.equals(service)))
        .go();
  }

  /// Delete ALL user data: library, anime cache, watch progress, downloads,
  /// tracking accounts, sync queue.
  Future<void> deleteAllUserData() async {
    await delete(userLibraryTable).go();
    await delete(watchProgressTable).go();
    await delete(downloadTasksTable).go();
    await delete(trackingSyncQueueTable).go();
    await delete(trackingAccountsTable).go();
    await delete(animeTable).go();
  }
}

/// Open a persistent SQLite database stored in the app's documents directory.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFolder = Directory(p.join(dir.path, 'NijiStream'));
    if (!await dbFolder.exists()) {
      await dbFolder.create(recursive: true);
    }
    final file = File(p.join(dbFolder.path, 'nijistream.db'));
    return NativeDatabase.createInBackground(file, logStatements: false);
  });
}


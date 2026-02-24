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
    EpisodesTable,
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        // Create all tables on first launch.
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Future migrations go here.
        // Example:
        // if (from < 2) {
        //   await m.addColumn(animeTable, animeTable.newColumn);
        // }
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
  Future<void> upsertLibraryEntry({
    required String animeId,
    required String status,
    int progress = 0,
    double score = 0.0,
  }) async {
    final existing = await getLibraryEntry(animeId);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (existing != null) {
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
  // Download helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Watch all download tasks ordered by creation time (newest first).
  Stream<List<DownloadTasksTableData>> watchDownloadTasks() {
    return (select(downloadTasksTable)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Remove a download task by id.
  Future<int> deleteDownloadTask(int id) =>
      (delete(downloadTasksTable)..where((t) => t.id.equals(id))).go();
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

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

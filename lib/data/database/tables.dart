/// NijiStream — drift (SQLite) table definitions.
///
/// **How drift works (quick primer):**
/// drift is a code-generation-based SQLite wrapper. You define your tables as
/// Dart classes that extend `Table`, and drift generates type-safe query code.
/// After modifying this file, run:
///   `dart run build_runner build`
/// to regenerate `app_database.g.dart`.
library;

import 'package:drift/drift.dart';

// ═══════════════════════════════════════════════════════════════════════
// TABLE: anime
// Stores anime metadata fetched from extensions.
// ═══════════════════════════════════════════════════════════════════════
class AnimeTable extends Table {
  @override
  String get tableName => 'anime';

  /// Composite key: `{extension_id}:{source_anime_id}`
  TextColumn get id => text()();
  TextColumn get extensionId => text()();
  TextColumn get sourceUrl => text().withDefault(const Constant(''))();
  TextColumn get title => text()();
  TextColumn get titleAlt => text().nullable()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get bannerUrl => text().nullable()();
  TextColumn get synopsis => text().nullable()();
  /// "airing", "completed", "upcoming"
  TextColumn get status => text().nullable()();
  IntColumn get episodeCount => integer().nullable()();
  RealColumn get rating => real().nullable()();
  /// JSON array stored as string, e.g. '["Action","Adventure"]'
  TextColumn get genres => text().nullable()();
  IntColumn get anilistId => integer().nullable()();
  IntColumn get malId => integer().nullable()();
  TextColumn get kitsuId => text().nullable()();
  /// Unix timestamp (seconds)
  IntColumn get updatedAt => integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch ~/ 1000))();

  @override
  Set<Column> get primaryKey => {id};
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE: user_library
// ═══════════════════════════════════════════════════════════════════════
class UserLibraryTable extends Table {
  @override
  String get tableName => 'user_library';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get animeId => text().references(AnimeTable, #id)();
  /// watching, plan_to_watch, completed, on_hold, dropped
  TextColumn get status => text().withDefault(const Constant('plan_to_watch'))();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  RealColumn get score => real().withDefault(const Constant(0.0))();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get updatedAt => integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch ~/ 1000))();
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE: watch_progress
// Tracks per-episode playback position for resume functionality.
// No FK constraints — episode IDs are soft references to extension runtime objects.
// ═══════════════════════════════════════════════════════════════════════
class WatchProgressTable extends Table {
  @override
  String get tableName => 'watch_progress';

  IntColumn get id => integer().autoIncrement()();
  /// Composite key: `{extensionId}:{animeId}`
  TextColumn get animeId => text()();
  /// Extension episode ID (e.g. `/watch/one-piece/1`)
  TextColumn get episodeId => text()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  /// 0 = not completed, 1 = completed
  IntColumn get completed => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch ~/ 1000))();
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE: download_tasks
// ═══════════════════════════════════════════════════════════════════════
class DownloadTasksTable extends Table {
  @override
  String get tableName => 'download_tasks';

  IntColumn get id => integer().autoIncrement()();
  /// Composite episode key: `{extensionId}:{episodeId}` — plain text, no FK.
  TextColumn get episodeId => text()();
  /// Human-readable anime title for display in the downloads screen.
  TextColumn get animeTitle => text().nullable()();
  /// Episode number for display in the downloads screen.
  IntColumn get episodeNumber => integer().nullable()();
  /// Anime cover image URL for the downloads grid.
  TextColumn get coverUrl => text().nullable()();
  TextColumn get url => text()();
  TextColumn get filePath => text().withDefault(const Constant(''))();
  /// queued, downloading, paused, completed, failed
  TextColumn get status => text().withDefault(const Constant('queued'))();
  RealColumn get progress => real().withDefault(const Constant(0.0))();
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch ~/ 1000))();
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE: tracking_accounts
// Stores OAuth account metadata (tokens live in FlutterSecureStorage).
// ═══════════════════════════════════════════════════════════════════════
class TrackingAccountsTable extends Table {
  @override
  String get tableName => 'tracking_accounts';

  /// "anilist", "mal", "kitsu"
  TextColumn get id => text()();
  TextColumn get service => text()();
  TextColumn get username => text().nullable()();
  /// Tokens are intentionally nullable — sensitive tokens are stored in
  /// FlutterSecureStorage, not here.
  TextColumn get accessToken => text().nullable()();
  TextColumn get refreshToken => text().nullable()();
  IntColumn get tokenExpiresAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE: tracking_sync_queue
// Offline-first queue for tracking updates.
// ═══════════════════════════════════════════════════════════════════════
class TrackingSyncQueueTable extends Table {
  @override
  String get tableName => 'tracking_sync_queue';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackingAccountId => text().references(TrackingAccountsTable, #id)();
  TextColumn get animeId => text().references(AnimeTable, #id)();
  /// update_status, update_progress, update_score
  TextColumn get action => text()();
  /// JSON payload
  TextColumn get payload => text()();
  IntColumn get createdAt => integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch ~/ 1000))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE: extensions
// Installed extension metadata.
// ═══════════════════════════════════════════════════════════════════════
class ExtensionsTable extends Table {
  @override
  String get tableName => 'extensions';

  /// Extension manifest id, e.g. "com.example.animesource"
  TextColumn get id => text()();
  TextColumn get repoId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get version => text()();
  TextColumn get lang => text().withDefault(const Constant('en'))();
  TextColumn get jsPath => text()();
  TextColumn get iconUrl => text().nullable()();
  /// 0 = disabled, 1 = enabled
  IntColumn get enabled => integer().withDefault(const Constant(1))();
  IntColumn get installedAt => integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch ~/ 1000))();

  @override
  Set<Column> get primaryKey => {id};
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE: extension_repos
// URLs for extension repository JSON indexes.
// ═══════════════════════════════════════════════════════════════════════
class ExtensionReposTable extends Table {
  @override
  String get tableName => 'extension_repos';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  IntColumn get lastSyncedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

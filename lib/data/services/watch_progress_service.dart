/// NijiStream — Watch progress persistence service.
///
/// Saves and restores episode playback positions using the drift SQLite
/// database. Backed by [WatchProgressTable] for durability (survives
/// app cache clears unlike SharedPreferences).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';

/// A saved playback position for a single episode.
class WatchProgressEntry {
  final int positionMs;
  final int durationMs;

  /// True when the user has watched >90% of the episode.
  final bool completed;

  const WatchProgressEntry({
    required this.positionMs,
    required this.durationMs,
    this.completed = false,
  });
}

/// Persists and retrieves episode watch progress via the SQLite database.
class WatchProgressService {
  final AppDatabase _db;

  WatchProgressService(this._db);

  /// Load the saved progress for an episode. Returns null if none exists.
  Future<WatchProgressEntry?> load(
    String extensionId,
    String episodeId,
  ) async {
    final animeId = extensionId; // stored as extensionId in this context
    final row = await _db.getWatchProgress(animeId, episodeId);
    if (row == null) return null;
    return WatchProgressEntry(
      positionMs: row.positionMs,
      durationMs: row.durationMs,
      completed: row.completed == 1,
    );
  }

  /// Persist the current playback position for an episode.
  Future<void> save(
    String extensionId,
    String episodeId,
    WatchProgressEntry entry,
  ) async {
    await _db.upsertWatchProgress(
      animeId: extensionId,
      episodeId: episodeId,
      positionMs: entry.positionMs,
      durationMs: entry.durationMs,
      completed: entry.completed,
    );
  }

  /// Mark an episode as completed.
  Future<void> markCompleted(String extensionId, String episodeId) async {
    final existing = await load(extensionId, episodeId);
    await save(
      extensionId,
      episodeId,
      WatchProgressEntry(
        positionMs: existing?.positionMs ?? 0,
        durationMs: existing?.durationMs ?? 0,
        completed: true,
      ),
    );
  }
}

/// Riverpod provider for [WatchProgressService].
final watchProgressServiceProvider = Provider<WatchProgressService>((ref) {
  return WatchProgressService(ref.read(databaseProvider));
});

/// NijiStream — Watch progress persistence service.
///
/// Saves and restores episode playback positions using SharedPreferences,
/// enabling seamless resume across app sessions.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
        'positionMs': positionMs,
        'durationMs': durationMs,
        'completed': completed,
      };

  factory WatchProgressEntry.fromJson(Map<String, dynamic> json) {
    return WatchProgressEntry(
      positionMs: json['positionMs'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
    );
  }
}

/// Persists and retrieves episode watch progress via SharedPreferences.
class WatchProgressService {
  static const _prefix = 'niji_wp__';

  /// Build the SharedPreferences key for an episode.
  String _key(String extensionId, String episodeId) =>
      '$_prefix${extensionId}__$episodeId';

  /// Load the saved progress for an episode. Returns null if none exists.
  Future<WatchProgressEntry?> load(
    String extensionId,
    String episodeId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(extensionId, episodeId));
    if (raw == null) return null;
    try {
      return WatchProgressEntry.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Persist the current playback position for an episode.
  Future<void> save(
    String extensionId,
    String episodeId,
    WatchProgressEntry entry,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(extensionId, episodeId),
      jsonEncode(entry.toJson()),
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

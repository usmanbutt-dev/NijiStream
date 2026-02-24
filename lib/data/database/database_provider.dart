/// NijiStream — Riverpod provider for the AppDatabase singleton.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Provides the single [AppDatabase] instance for the lifetime of the app.
///
/// Access from any widget or provider via:
/// ```dart
/// final db = ref.read(databaseProvider);
/// ```
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// NijiStream — Riverpod providers for the extension system.
///
/// **How Riverpod providers work (quick primer):**
/// A Provider is a globally accessible container for a value. Widgets access
/// it via `ref.watch(providerName)` which automatically rebuilds when the
/// value changes. We use `StateNotifier` providers for mutable state and
/// plain `Provider` for singletons.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/extension_repository.dart';

/// Singleton provider for the [ExtensionRepository].
///
/// Access it in any widget:
/// ```dart
/// final repo = ref.read(extensionRepositoryProvider);
/// ```
final extensionRepositoryProvider = Provider<ExtensionRepository>((ref) {
  final repo = ExtensionRepository();
  // Dispose all runtimes when the provider is disposed.
  ref.onDispose(() => repo.disposeAll());
  return repo;
});

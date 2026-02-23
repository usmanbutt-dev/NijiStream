/// NijiStream — Extension repository (install, update, remove, load).
///
/// This is the high-level service that manages the extension lifecycle:
/// 1. Fetching repo indexes from GitHub
/// 2. Installing/updating/removing extensions (downloads .js files)
/// 3. Loading installed extensions into JS runtimes
/// 4. Providing a unified interface to query all loaded extensions
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../engine/js_runtime.dart';
import '../models/extension_manifest.dart';

/// Manages the full extension lifecycle.
///
/// **Usage pattern (from Riverpod providers):**
/// ```dart
/// final repo = ExtensionRepository();
/// await repo.init();
/// await repo.loadAllExtensions();
/// final results = await repo.searchAll('naruto', 1);
/// ```
class ExtensionRepository {
  final Dio _dio;

  /// All currently loaded extension runtimes, keyed by extension ID.
  final Map<String, JsRuntime> _runtimes = {};

  /// The directory where extension .js files are stored.
  late final Directory _extensionsDir;

  /// Whether [init] has been called.
  bool _initialized = false;

  ExtensionRepository({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ));

  // ═══════════════════════════════════════════════════════════════════
  // Initialization
  // ═══════════════════════════════════════════════════════════════════

  /// Initialize the extension directory.
  /// Must be called before any other methods.
  Future<void> init() async {
    if (_initialized) return;
    final appDir = await getApplicationDocumentsDirectory();
    _extensionsDir = Directory(p.join(appDir.path, 'NijiStream', 'extensions'));
    if (!await _extensionsDir.exists()) {
      await _extensionsDir.create(recursive: true);
    }
    _initialized = true;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Repository fetching
  // ═══════════════════════════════════════════════════════════════════

  /// Fetch an extension repository index from a URL.
  ///
  /// Returns the parsed [ExtensionRepo] with all available extensions.
  Future<ExtensionRepo> fetchRepoIndex(String url) async {
    try {
      final response = await _dio.get<String>(url);
      final json = jsonDecode(response.data!) as Map<String, dynamic>;
      return ExtensionRepo.fromJson(json);
    } catch (e) {
      throw Exception('Failed to fetch repo index: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Installation
  // ═══════════════════════════════════════════════════════════════════

  /// Install an extension by downloading its .js file.
  ///
  /// Returns the local file path where the extension was saved.
  Future<String> installExtension(ExtensionRepoEntry entry) async {
    _ensureInit();
    try {
      final response = await _dio.get<String>(entry.url);
      final filePath = p.join(_extensionsDir.path, '${entry.id}.js');
      final file = File(filePath);
      await file.writeAsString(response.data!);
      return filePath;
    } catch (e) {
      throw Exception('Failed to install extension "${entry.name}": $e');
    }
  }

  /// Remove an installed extension.
  Future<void> removeExtension(String extensionId) async {
    _ensureInit();

    // Unload runtime if loaded.
    final runtime = _runtimes.remove(extensionId);
    runtime?.dispose();

    // Delete the .js file.
    final filePath = p.join(_extensionsDir.path, '$extensionId.js');
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Loading
  // ═══════════════════════════════════════════════════════════════════

  /// Load a single extension from its .js file path.
  ///
  /// Creates a new [JsRuntime], loads the JS code, and adds it to
  /// the active runtimes map.
  Future<ExtensionManifest?> loadExtension(
    String extensionId,
    String jsFilePath,
  ) async {
    try {
      final file = File(jsFilePath);
      if (!await file.exists()) {
        debugPrint('Extension file not found: $jsFilePath');
        return null;
      }

      final jsCode = await file.readAsString();
      final runtime = JsRuntime();
      await runtime.init();
      await runtime.loadExtension(jsCode);

      // Dispose old runtime if reloading.
      _runtimes[extensionId]?.dispose();
      _runtimes[extensionId] = runtime;

      return runtime.manifest;
    } catch (e) {
      debugPrint('Failed to load extension $extensionId: $e');
      return null;
    }
  }

  /// Load all .js files from the extensions directory.
  Future<List<ExtensionManifest>> loadAllExtensions() async {
    _ensureInit();
    final manifests = <ExtensionManifest>[];

    final files = _extensionsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'));

    for (final file in files) {
      final extensionId = p.basenameWithoutExtension(file.path);
      final manifest = await loadExtension(extensionId, file.path);
      if (manifest != null) {
        manifests.add(manifest);
      }
    }

    return manifests;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Querying (unified across all loaded extensions)
  // ═══════════════════════════════════════════════════════════════════

  /// Search all loaded extensions in parallel and aggregate results.
  ///
  /// Returns a map of extension ID → search response.
  Future<Map<String, ExtensionSearchResponse>> searchAll(
    String query,
    int page, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final results = <String, ExtensionSearchResponse>{};

    // Query all extensions concurrently with a timeout.
    final futures = _runtimes.entries.map((entry) async {
      try {
        final response = await entry.value
            .search(query, page)
            .timeout(timeout);
        return MapEntry(entry.key, response);
      } catch (e) {
        debugPrint('Search failed for ${entry.key}: $e');
        return MapEntry(entry.key, const ExtensionSearchResponse());
      }
    });

    final entries = await Future.wait(futures);
    for (final entry in entries) {
      results[entry.key] = entry.value;
    }

    return results;
  }

  /// Get anime detail from a specific extension.
  Future<ExtensionAnimeDetail?> getDetail(
    String extensionId,
    String animeId,
  ) async {
    final runtime = _runtimes[extensionId];
    if (runtime == null) return null;
    try {
      return await runtime.getDetail(animeId);
    } catch (e) {
      debugPrint('getDetail failed for $extensionId: $e');
      return null;
    }
  }

  /// Get video sources from a specific extension.
  Future<ExtensionVideoResponse?> getVideoSources(
    String extensionId,
    String episodeUrl,
  ) async {
    final runtime = _runtimes[extensionId];
    if (runtime == null) return null;
    try {
      return await runtime.getVideoSources(episodeUrl);
    } catch (e) {
      debugPrint('getVideoSources failed for $extensionId: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // State accessors
  // ═══════════════════════════════════════════════════════════════════

  /// List of loaded extension IDs.
  List<String> get loadedExtensionIds => _runtimes.keys.toList();

  /// Check if a specific extension is loaded.
  bool isLoaded(String extensionId) => _runtimes.containsKey(extensionId);

  /// Get the manifest for a loaded extension.
  ExtensionManifest? getManifest(String extensionId) {
    return _runtimes[extensionId]?.manifest;
  }

  /// Number of loaded extensions.
  int get loadedCount => _runtimes.length;

  /// Dispose all runtimes (call on app shutdown).
  void disposeAll() {
    for (final runtime in _runtimes.values) {
      runtime.dispose();
    }
    _runtimes.clear();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Private helpers
  // ═══════════════════════════════════════════════════════════════════

  void _ensureInit() {
    if (!_initialized) {
      throw StateError(
        'ExtensionRepository not initialized. Call init() first.',
      );
    }
  }
}

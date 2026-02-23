/// NijiStream — QuickJS runtime wrapper.
///
/// Wraps `flutter_js` to manage a sandboxed JavaScript execution context
/// for a **single extension**. Each extension gets its own [JsRuntime]
/// instance with bridge functions registered.
///
/// **How flutter_js works (quick primer):**
/// `flutter_js` provides `getJavascriptRuntime()` which gives you a
/// QuickJS context. You can:
///   - `evaluate(code)` — run JS code and get the result
///   - `onMessage(channel, callback)` — register Dart functions callable
///     from JS via `sendMessage(channel, args)`
///
/// We use `evaluate()` to load the extension's .js file, then call
/// its methods (search, getDetail, etc.) by evaluating more JS code
/// that invokes those methods and returns JSON results.
library;

import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

import '../api/bridge_functions.dart';
import '../models/extension_manifest.dart';

/// A sandboxed JS runtime for running a single extension.
class JsRuntime {
  /// The flutter_js runtime instance.
  late final JavascriptRuntime _runtime;

  /// Bridge functions (HTTP, HTML parsing, crypto).
  final BridgeFunctions _bridge;

  /// The extension's manifest, extracted after loading.
  ExtensionManifest? manifest;

  /// Whether the runtime has been initialized with extension code.
  bool _loaded = false;

  JsRuntime({BridgeFunctions? bridge})
      : _bridge = bridge ?? BridgeFunctions();

  /// Initialize the QuickJS runtime and register all bridge functions.
  ///
  /// Call this once before [loadExtension]. We separate init from
  /// construction so it can be async.
  Future<void> init() async {
    _runtime = getJavascriptRuntime();
    _registerBridgeFunctions();
  }

  /// Load and execute an extension's JavaScript source code.
  ///
  /// After loading, the extension's `manifest` and `AnimeSource` class
  /// are available in the JS context.
  Future<void> loadExtension(String jsCode) async {
    // Inject the JS helper layer that bridges Dart calls to/from JS.
    // This provides the `http`, `parseHtml`, `crypto`, and `log` globals
    // that extensions expect.
    _runtime.evaluate(_bridgeJsCode);

    // Load the extension source code.
    final result = _runtime.evaluate(jsCode);
    if (result.isError) {
      throw Exception('Failed to load extension JS: ${result.stringResult}');
    }

    // Extract the manifest.
    final manifestResult = _runtime.evaluate('JSON.stringify(manifest)');
    if (!manifestResult.isError) {
      try {
        final json = jsonDecode(manifestResult.stringResult) as Map<String, dynamic>;
        manifest = ExtensionManifest.fromJson(json);
      } catch (_) {
        // Manifest parsing failed — extension may still work.
      }
    }

    _loaded = true;
  }

  /// Search for anime using the extension's `search(query, page)` method.
  Future<ExtensionSearchResponse> search(String query, int page) async {
    _ensureLoaded();
    final escaped = _escapeJs(query);
    final result = _runtime.evaluate('''
      (async () => {
        const source = new AnimeSource();
        const result = await source.search("$escaped", $page);
        return JSON.stringify(result);
      })()
    ''');
    return _parseSearchResponse(await _resolveAsyncResult(result));
  }

  /// Get anime details including episode list.
  Future<ExtensionAnimeDetail> getDetail(String animeId) async {
    _ensureLoaded();
    final escaped = _escapeJs(animeId);
    final result = _runtime.evaluate('''
      (async () => {
        const source = new AnimeSource();
        const result = await source.getDetail("$escaped");
        return JSON.stringify(result);
      })()
    ''');
    return _parseDetailResponse(await _resolveAsyncResult(result));
  }

  /// Get video sources for an episode.
  Future<ExtensionVideoResponse> getVideoSources(String episodeUrl) async {
    _ensureLoaded();
    final escaped = _escapeJs(episodeUrl);
    final result = _runtime.evaluate('''
      (async () => {
        const source = new AnimeSource();
        const result = await source.getVideoSources("$escaped");
        return JSON.stringify(result);
      })()
    ''');
    return _parseVideoResponse(await _resolveAsyncResult(result));
  }

  /// Get latest anime (optional extension method).
  Future<ExtensionSearchResponse> getLatest(int page) async {
    _ensureLoaded();
    final hasMethod = _runtime.evaluate(
      'typeof AnimeSource.prototype.getLatest === "function"',
    );
    if (hasMethod.stringResult != 'true') {
      return const ExtensionSearchResponse();
    }
    final result = _runtime.evaluate('''
      (async () => {
        const source = new AnimeSource();
        const result = await source.getLatest($page);
        return JSON.stringify(result);
      })()
    ''');
    return _parseSearchResponse(await _resolveAsyncResult(result));
  }

  /// Get popular anime (optional extension method).
  Future<ExtensionSearchResponse> getPopular(int page) async {
    _ensureLoaded();
    final hasMethod = _runtime.evaluate(
      'typeof AnimeSource.prototype.getPopular === "function"',
    );
    if (hasMethod.stringResult != 'true') {
      return const ExtensionSearchResponse();
    }
    final result = _runtime.evaluate('''
      (async () => {
        const source = new AnimeSource();
        const result = await source.getPopular($page);
        return JSON.stringify(result);
      })()
    ''');
    return _parseSearchResponse(await _resolveAsyncResult(result));
  }

  /// Dispose of the JS runtime and free resources.
  void dispose() {
    _runtime.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // PRIVATE: Bridge registration
  // ═══════════════════════════════════════════════════════════════════

  /// Register all Dart bridge functions into the JS context.
  ///
  /// flutter_js's `onMessage` lets us define named channels. The JS side
  /// calls `sendMessage(channel, JSON.stringify(args))` and the Dart
  /// callback receives the args string and returns a result.
  void _registerBridgeFunctions() {
    // ── http.get ──
    _runtime.onMessage('http_get', (args) {
      final parsed = jsonDecode(args) as Map<String, dynamic>;
      final url = parsed['url'] as String;
      final headers = (parsed['headers'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString()));
      // flutter_js's onMessage is synchronous, so we need a workaround
      // for async bridge calls. We'll use a pending promise pattern —
      // see _bridgeJsCode for the JS side.
      _bridge.httpGet(url, headers).then((result) {
        _runtime.evaluate(
          '_resolvePending("http_get", ${jsonEncode(result)})',
        );
      });
      return '';
    });

    // ── http.post ──
    _runtime.onMessage('http_post', (args) {
      final parsed = jsonDecode(args) as Map<String, dynamic>;
      final url = parsed['url'] as String;
      final body = parsed['body'] as String? ?? '';
      final headers = (parsed['headers'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString()));
      _bridge.httpPost(url, body, headers).then((result) {
        _runtime.evaluate(
          '_resolvePending("http_post", ${jsonEncode(result)})',
        );
      });
      return '';
    });

    // ── parseHtml ──
    _runtime.onMessage('parse_html', (args) {
      return _bridge.parseHtml(args);
    });

    // ── querySelectorAll ──
    _runtime.onMessage('query_selector_all', (args) {
      final parsed = jsonDecode(args) as Map<String, dynamic>;
      return _bridge.querySelectorAll(
        parsed['html'] as String,
        parsed['selector'] as String,
      );
    });

    // ── querySelector ──
    _runtime.onMessage('query_selector', (args) {
      final parsed = jsonDecode(args) as Map<String, dynamic>;
      return _bridge.querySelector(
        parsed['html'] as String,
        parsed['selector'] as String,
      ) ?? 'null';
    });

    // ── crypto.md5 ──
    _runtime.onMessage('crypto_md5', (args) {
      return _bridge.cryptoMd5(args);
    });

    // ── crypto.base64Encode ──
    _runtime.onMessage('crypto_base64_encode', (args) {
      return _bridge.cryptoBase64Encode(args);
    });

    // ── crypto.base64Decode ──
    _runtime.onMessage('crypto_base64_decode', (args) {
      return _bridge.cryptoBase64Decode(args);
    });

    // ── log ──
    _runtime.onMessage('niji_log', (args) {
      // ignore: avoid_print
      print('[Extension] $args');
      return '';
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // PRIVATE: Helpers
  // ═══════════════════════════════════════════════════════════════════

  void _ensureLoaded() {
    if (!_loaded) {
      throw StateError('Extension not loaded. Call loadExtension() first.');
    }
  }

  /// Escape a string for safe embedding in JS string literals.
  String _escapeJs(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  /// Resolve an async JS result.
  ///
  /// flutter_js handles Promises internally, but we may need to
  /// handle the executePendingJob() loop for async operations.
  Future<String> _resolveAsyncResult(JsEvalResult result) async {
    if (result.isError) {
      throw Exception('JS execution error: ${result.stringResult}');
    }

    // Execute pending async jobs (for Promise resolution).
    _runtime.executePendingJob();

    return result.stringResult;
  }

  ExtensionSearchResponse _parseSearchResponse(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>?)
              ?.map((e) => ExtensionSearchResult.fromJson(
                  e as Map<String, dynamic>))
              .toList() ??
          [];
      return ExtensionSearchResponse(
        hasNextPage: data['hasNextPage'] as bool? ?? false,
        results: results,
      );
    } catch (e) {
      return const ExtensionSearchResponse();
    }
  }

  ExtensionAnimeDetail _parseDetailResponse(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final episodes = (data['episodes'] as List<dynamic>?)
              ?.map(
                  (e) => ExtensionEpisode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final genres = (data['genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      return ExtensionAnimeDetail(
        title: data['title'] as String? ?? '',
        coverUrl: data['cover'] as String?,
        bannerUrl: data['banner'] as String?,
        synopsis: data['synopsis'] as String?,
        genres: genres,
        status: data['status'] as String?,
        episodes: episodes,
      );
    } catch (e) {
      throw Exception('Failed to parse anime detail: $e');
    }
  }

  ExtensionVideoResponse _parseVideoResponse(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final sources = (data['sources'] as List<dynamic>?)
              ?.map((e) =>
                  ExtensionVideoSource.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final subtitles = (data['subtitles'] as List<dynamic>?)
              ?.map((e) =>
                  ExtensionSubtitle.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      return ExtensionVideoResponse(sources: sources, subtitles: subtitles);
    } catch (e) {
      return const ExtensionVideoResponse();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// JS bridge code injected into every extension runtime.
//
// This provides the global `http`, `parseHtml`, `crypto`, and `log`
// objects that extensions expect to use.
// ═══════════════════════════════════════════════════════════════════════

const _bridgeJsCode = r'''
// ── Pending promise system for async bridge calls ──
// Since flutter_js's sendMessage is synchronous but HTTP calls are async,
// we use a simple polling-based promise resolution pattern.

var _pendingCallbacks = {};
var _pendingId = 0;

function _resolvePending(channel, result) {
  if (_pendingCallbacks[channel]) {
    _pendingCallbacks[channel](result);
    delete _pendingCallbacks[channel];
  }
}

// ── HTTP bridge ──
var http = {
  get: function(url, headers) {
    var args = JSON.stringify({ url: url, headers: headers || {} });
    sendMessage("http_get", args);
    // Note: In the synchronous flutter_js model, the response will be
    // available after the Dart side processes the message.
    // For MVP, we use the synchronous sendMessage return value.
    return sendMessage("http_get", args);
  },
  post: function(url, body, headers) {
    var args = JSON.stringify({ url: url, body: body, headers: headers || {} });
    return sendMessage("http_post", args);
  }
};

// ── HTML parser bridge ──
// Returns a helper object with querySelector/querySelectorAll methods.
function parseHtml(htmlString) {
  return {
    _html: htmlString,
    querySelector: function(selector) {
      var result = sendMessage("query_selector", JSON.stringify({
        html: this._html,
        selector: selector
      }));
      if (result === "null" || !result) return null;
      var el = JSON.parse(result);
      return _wrapElement(el, this._html);
    },
    querySelectorAll: function(selector) {
      var result = sendMessage("query_selector_all", JSON.stringify({
        html: this._html,
        selector: selector
      }));
      var elements = JSON.parse(result);
      var self = this;
      return elements.map(function(el) { return _wrapElement(el, self._html); });
    },
    text: (function() {
      var parsed = sendMessage("parse_html", htmlString);
      return JSON.parse(parsed).text || "";
    })()
  };
}

// Wrap a parsed element JSON in a helper with attribute access.
function _wrapElement(el, originalHtml) {
  return {
    tag: el.tag,
    text: el.text || "",
    html: el.html || "",
    attrs: el.attrs || {},
    children: (el.children || []).map(function(c) {
      return _wrapElement(c, originalHtml);
    }),
    getAttribute: function(name) {
      return (el.attrs || {})[name] || null;
    },
    querySelector: function(selector) {
      // Re-query using this element's inner HTML as the base document.
      var result = sendMessage("query_selector", JSON.stringify({
        html: el.html || "",
        selector: selector
      }));
      if (result === "null" || !result) return null;
      return _wrapElement(JSON.parse(result), el.html || "");
    },
    querySelectorAll: function(selector) {
      var result = sendMessage("query_selector_all", JSON.stringify({
        html: el.html || "",
        selector: selector
      }));
      var elements = JSON.parse(result);
      return elements.map(function(c) {
        return _wrapElement(c, el.html || "");
      });
    }
  };
}

// ── Crypto bridge ──
var crypto = {
  md5: function(input) {
    return sendMessage("crypto_md5", input);
  },
  base64Encode: function(input) {
    return sendMessage("crypto_base64_encode", input);
  },
  base64Decode: function(input) {
    return sendMessage("crypto_base64_decode", input);
  }
};

// ── Logging ──
function log(message) {
  sendMessage("niji_log", String(message));
}
''';

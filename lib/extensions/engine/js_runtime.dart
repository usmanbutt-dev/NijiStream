/// NijiStream — QuickJS runtime wrapper.
///
/// Wraps `flutter_js` to manage a sandboxed JavaScript execution context
/// for a **single extension**. Each extension gets its own [JsRuntime]
/// instance with bridge functions registered.
///
/// ## How flutter_js / QuickJS works (important nuances)
///
/// 1. `evaluate(code)` is synchronous. Evaluating an `async` IIFE returns
///    a `[object Promise]` JsEvalResult immediately — the Promise is not
///    yet resolved.
///
/// 2. `onMessage(channel, handler)` registers a Dart callback. The JS side
///    calls `sendMessage(channel, jsonString)`. IMPORTANT: flutter_js
///    **automatically `jsonDecode`s** the second argument before calling
///    the Dart handler, so the handler receives a `dynamic` (Map/List/String)
///    — NOT a raw JSON string.
///
/// 3. `handlePromise(result)` is the official flutter_js API for awaiting a
///    Promise returned by `evaluate`. It polls `executePendingJob()` via
///    `Timer.periodic` until `FLUTTER_NATIVEJS_MakeQuerablePromise` reports
///    the Promise is no longer pending, then reads the value.
///    We use this for every async extension call.
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
  Future<void> init() async {
    _runtime = getJavascriptRuntime();
    _registerBridgeFunctions();
  }

  /// Load and execute an extension's JavaScript source code.
  Future<void> loadExtension(String jsCode) async {
    _runtime.evaluate(_bridgeJsCode);

    final result = _runtime.evaluate(jsCode);
    if (result.isError) {
      throw Exception('Failed to load extension JS: ${result.stringResult}');
    }

    final manifestResult = _runtime.evaluate('JSON.stringify(manifest)');
    if (!manifestResult.isError) {
      try {
        final json =
            jsonDecode(manifestResult.stringResult) as Map<String, dynamic>;
        manifest = ExtensionManifest.fromJson(json);
      } catch (_) {}
    }

    _loaded = true;
  }

  /// Search for anime using the extension's `search(query, page)` method.
  Future<ExtensionSearchResponse> search(String query, int page) async {
    _ensureLoaded();
    final escaped = _escapeJs(query);
    final json = await _callAsync(
        'new AnimeSource().search("$escaped", $page)');
    return _parseSearchResponse(json);
  }

  /// Get anime details including episode list.
  Future<ExtensionAnimeDetail> getDetail(String animeId) async {
    _ensureLoaded();
    final escaped = _escapeJs(animeId);
    final json = await _callAsync(
        'new AnimeSource().getDetail("$escaped")');
    return _parseDetailResponse(json);
  }

  /// Get video sources for an episode.
  Future<ExtensionVideoResponse> getVideoSources(String episodeUrl) async {
    _ensureLoaded();
    final escaped = _escapeJs(episodeUrl);
    final json = await _callAsync(
        'new AnimeSource().getVideoSources("$escaped")');
    return _parseVideoResponse(json);
  }

  /// Get latest anime (optional extension method).
  Future<ExtensionSearchResponse> getLatest(int page) async {
    _ensureLoaded();
    final hasMethod = _runtime.evaluate(
        'typeof AnimeSource.prototype.getLatest === "function"');
    if (hasMethod.stringResult != 'true') return const ExtensionSearchResponse();
    final json = await _callAsync('new AnimeSource().getLatest($page)');
    return _parseSearchResponse(json);
  }

  /// Get popular anime (optional extension method).
  Future<ExtensionSearchResponse> getPopular(int page) async {
    _ensureLoaded();
    final hasMethod = _runtime.evaluate(
        'typeof AnimeSource.prototype.getPopular === "function"');
    if (hasMethod.stringResult != 'true') return const ExtensionSearchResponse();
    final json = await _callAsync('new AnimeSource().getPopular($page)');
    return _parseSearchResponse(json);
  }

  /// Dispose of the JS runtime and free resources.
  void dispose() {
    _runtime.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // PRIVATE: Bridge registration
  // ═══════════════════════════════════════════════════════════════════

  void _registerBridgeFunctions() {
    // NOTE: flutter_js automatically jsonDecodes the message string before
    // calling the handler. Handlers receive a decoded dynamic (Map/List/String).

    // ── http.get ──
    _runtime.onMessage('http_get', (dynamic args) {
      // args is already a Map (decoded from JSON by flutter_js)
      final map = args as Map<dynamic, dynamic>;
      final id = map['id'] as String;
      final data = map['data'] as Map<dynamic, dynamic>;
      final url = data['url'] as String;
      final rawHeaders = data['headers'] as Map<dynamic, dynamic>?;
      final headers = rawHeaders?.map((k, v) => MapEntry(k.toString(), v.toString()));
      _bridge.httpGet(url, headers).then((result) {
        _runtime.evaluate('_resolvePending(${jsonEncode(id)}, ${jsonEncode(result)})');
        _runtime.executePendingJob();
      });
      return '';
    });

    // ── http.post ──
    _runtime.onMessage('http_post', (dynamic args) {
      final map = args as Map<dynamic, dynamic>;
      final id = map['id'] as String;
      final data = map['data'] as Map<dynamic, dynamic>;
      final url = data['url'] as String;
      final body = data['body'] as String? ?? '';
      final rawHeaders = data['headers'] as Map<dynamic, dynamic>?;
      final headers = rawHeaders?.map((k, v) => MapEntry(k.toString(), v.toString()));
      _bridge.httpPost(url, body, headers).then((result) {
        _runtime.evaluate('_resolvePending(${jsonEncode(id)}, ${jsonEncode(result)})');
        _runtime.executePendingJob();
      });
      return '';
    });

    // ── parseHtml ──
    _runtime.onMessage('parse_html', (dynamic args) {
      return _bridge.parseHtml(args as String);
    });

    // ── querySelectorAll ──
    _runtime.onMessage('query_selector_all', (dynamic args) {
      final map = args as Map<dynamic, dynamic>;
      return _bridge.querySelectorAll(
        map['html'] as String,
        map['selector'] as String,
      );
    });

    // ── querySelector ──
    _runtime.onMessage('query_selector', (dynamic args) {
      final map = args as Map<dynamic, dynamic>;
      return _bridge.querySelector(
            map['html'] as String,
            map['selector'] as String,
          ) ??
          'null';
    });

    // ── crypto ──
    _runtime.onMessage('crypto_md5', (dynamic args) => _bridge.cryptoMd5(args as String));
    _runtime.onMessage('crypto_base64_encode', (dynamic args) => _bridge.cryptoBase64Encode(args as String));
    _runtime.onMessage('crypto_base64_decode', (dynamic args) => _bridge.cryptoBase64Decode(args as String));

    // ── log ──
    _runtime.onMessage('niji_log', (dynamic args) {
      // ignore: avoid_print
      print('[Extension] $args');
      return '';
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // PRIVATE: Async call helper
  // ═══════════════════════════════════════════════════════════════════

  void _ensureLoaded() {
    if (!_loaded) throw StateError('Extension not loaded. Call loadExtension() first.');
  }

  String _escapeJs(String input) => input
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r');

  /// Evaluate a JS expression that returns a Promise, await it using
  /// flutter_js's built-in `handlePromise`, then JSON-stringify the result.
  ///
  /// `jsExpr` must be a JS expression that evaluates to a Promise<object>.
  /// Example: `'new AnimeSource().search("naruto", 1)'`
  Future<String> _callAsync(String jsExpr) async {
    // Wrap in JSON.stringify so we get back a plain string.
    final promiseResult = _runtime.evaluate(
      '($jsExpr).then(function(r){ return JSON.stringify(r); })',
    );

    if (promiseResult.isError) {
      throw Exception('JS error: ${promiseResult.stringResult}');
    }

    // handlePromise polls executePendingJob until the Promise settles.
    final resolved = await _runtime.handlePromise(
      promiseResult,
      timeout: const Duration(seconds: 30),
    );

    if (resolved.isError) {
      throw Exception('JS async error: ${resolved.stringResult}');
    }

    // The resolved value is the JSON string from JSON.stringify.
    // handlePromise wraps it in another JSON.stringify internally, so
    // the stringResult may be a JSON-encoded string — unwrap if needed.
    var raw = resolved.stringResult;
    // If the result is a quoted JSON string (e.g. '"{\\"key\\":1}"'), unwrap it.
    if (raw.startsWith('"') && raw.endsWith('"')) {
      try {
        raw = jsonDecode(raw) as String;
      } catch (_) {}
    }
    return raw;
  }

  // ═══════════════════════════════════════════════════════════════════
  // PRIVATE: Response parsers
  // ═══════════════════════════════════════════════════════════════════

  ExtensionSearchResponse _parseSearchResponse(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>?)
              ?.map((e) =>
                  ExtensionSearchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      return ExtensionSearchResponse(
        hasNextPage: data['hasNextPage'] as bool? ?? false,
        results: results,
      );
    } catch (_) {
      return const ExtensionSearchResponse();
    }
  }

  ExtensionAnimeDetail _parseDetailResponse(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final episodes = (data['episodes'] as List<dynamic>?)
              ?.map((e) =>
                  ExtensionEpisode.fromJson(e as Map<String, dynamic>))
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
    } catch (_) {
      return const ExtensionVideoResponse();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// JS bridge code injected into every extension runtime.
// ═══════════════════════════════════════════════════════════════════════

const _bridgeJsCode = r'''
// ── HTTP bridge ──
// http.get / http.post return Promises resolved by the Dart side calling
// _resolvePending(id, result) back into the runtime.
var __httpPending = {};
var __httpNextId = 0;

function _resolvePending(id, result) {
  if (__httpPending[id]) {
    __httpPending[id](result);
    delete __httpPending[id];
  }
}

function __makeHttpPromise(channel, args) {
  var id = String(__httpNextId++);
  var p = new Promise(function(resolve) {
    __httpPending[id] = resolve;
  });
  sendMessage(channel, JSON.stringify({ id: id, data: args }));
  return p;
}

var http = {
  get: function(url, headers) {
    return __makeHttpPromise("http_get", { url: url, headers: headers || {} });
  },
  post: function(url, body, headers) {
    return __makeHttpPromise("http_post", { url: url, body: body || "", headers: headers || {} });
  }
};

// ── HTML parser bridge ──
function parseHtml(htmlString) {
  return {
    _html: htmlString,
    querySelector: function(selector) {
      var result = sendMessage("query_selector", JSON.stringify({
        html: this._html, selector: selector
      }));
      if (result === "null" || !result) return null;
      return _wrapElement(JSON.parse(result), this._html);
    },
    querySelectorAll: function(selector) {
      var result = sendMessage("query_selector_all", JSON.stringify({
        html: this._html, selector: selector
      }));
      var self = this;
      return JSON.parse(result).map(function(el) { return _wrapElement(el, self._html); });
    },
    get text() {
      return JSON.parse(sendMessage("parse_html", this._html)).text || "";
    }
  };
}

function _wrapElement(el, contextHtml) {
  return {
    tag: el.tag,
    text: el.text || "",
    html: el.html || "",
    attrs: el.attrs || {},
    getAttribute: function(name) { return (el.attrs || {})[name] || null; },
    querySelector: function(selector) {
      var result = sendMessage("query_selector", JSON.stringify({ html: el.html || "", selector: selector }));
      if (result === "null" || !result) return null;
      return _wrapElement(JSON.parse(result), el.html || "");
    },
    querySelectorAll: function(selector) {
      var result = sendMessage("query_selector_all", JSON.stringify({ html: el.html || "", selector: selector }));
      return JSON.parse(result).map(function(c) { return _wrapElement(c, el.html || ""); });
    }
  };
}

// ── Crypto bridge ──
var crypto = {
  md5: function(input) { return sendMessage("crypto_md5", JSON.stringify(input)); },
  base64Encode: function(input) { return sendMessage("crypto_base64_encode", JSON.stringify(input)); },
  base64Decode: function(input) { return sendMessage("crypto_base64_decode", JSON.stringify(input)); }
};

// ── Logging ──
function log(message) {
  sendMessage("niji_log", JSON.stringify(String(message)));
}
''';

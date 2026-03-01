/// NijiStream — Dart↔JavaScript bridge functions.
///
/// These functions are injected into the QuickJS runtime so that
/// extension JavaScript code can call them. Each function corresponds
/// to an API the extension contract expects (see spec §5.2).
///
/// **How the bridge works:**
/// 1. We register Dart functions as callable JS global functions.
/// 2. When extension JS calls e.g. `http.get(url)`, QuickJS routes it
///    back to our Dart code, which uses `dio` to make the request.
/// 3. The result is returned to JS as a string.
///
/// This is inherently sandboxed — extensions can only do network I/O
/// through these bridge functions and have no direct filesystem or
/// database access.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

/// All the Dart-side implementations that get bridged into JS.
///
/// Each extension runtime gets its own [BridgeFunctions] instance
/// with its own [Dio] client (allowing per-extension cookies / headers).
///
/// Call [cancelAll] when the owning runtime is being torn down to abort any
/// in-flight requests and avoid callbacks arriving after the JS context is gone.
class BridgeFunctions {
  final Dio _dio;
  final CancelToken _cancelToken = CancelToken();

  BridgeFunctions({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              },
            ));

  /// Cancel all in-flight requests. Call when the extension is unloaded.
  void cancelAll() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('Extension unloaded');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // http.get(url, headers?) → string
  // ═══════════════════════════════════════════════════════════════════

  /// Performs an HTTP GET request and returns the response body as a string.
  Future<String> httpGet(String url, [Map<String, String>? headers]) async {
    try {
      final response = await _dio.get<String>(
        url,
        cancelToken: _cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
        ),
      );
      return _sanitizeForJs(response.data ?? '');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return '{"error": "cancelled"}';
      return '{"error": "${_escapeJsonValue(e.message ?? 'unknown error')}"}';
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // http.post(url, body, headers?) → string
  // ═══════════════════════════════════════════════════════════════════

  /// Performs an HTTP POST request and returns the response body.
  Future<String> httpPost(
    String url,
    String body, [
    Map<String, String>? headers,
  ]) async {
    try {
      final response = await _dio.post<String>(
        url,
        data: body,
        cancelToken: _cancelToken,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            ...?headers,
          },
          responseType: ResponseType.plain,
        ),
      );
      return _sanitizeForJs(response.data ?? '');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return '{"error": "cancelled"}';
      return '{"error": "${_escapeJsonValue(e.message ?? 'unknown error')}"}';
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Response sanitization
  // ═══════════════════════════════════════════════════════════════════

  /// Remove control characters (U+0000–U+001F except tab/LF/CR) and the
  /// UTF-8 BOM (U+FEFF) from an HTTP response body. These break QuickJS's
  /// strict JSON.parse even though many servers emit them.
  static String _sanitizeForJs(String input) {
    // Fast path: skip allocation if nothing needs stripping.
    bool needsCleaning = false;
    for (int i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      if (c == 0xFEFF || (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D)) {
        needsCleaning = true;
        break;
      }
    }
    if (!needsCleaning) return input;

    final buf = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      // Drop BOM and non-printable control chars (keep \t \n \r).
      if (c == 0xFEFF) continue;
      if (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) continue;
      buf.writeCharCode(c);
    }
    return buf.toString();
  }

  /// Escape characters that would break a JSON string value.
  static String _escapeJsonValue(String input) {
    return input.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  // ═══════════════════════════════════════════════════════════════════
  // parseHtml(html) → JSON DOM representation
  // ═══════════════════════════════════════════════════════════════════

  /// Parses an HTML string and returns a JSON-encoded DOM representation.
  ///
  /// The JS side of the bridge wraps this JSON in a helper object that
  /// provides `querySelector`, `querySelectorAll`, `getAttribute`, `text`.
  /// We parse on the Dart side (using the `html` package) because QuickJS
  /// doesn't have a DOM parser.
  String parseHtml(String htmlString) {
    final document = html_parser.parse(htmlString);
    return jsonEncode(_elementToJson(document.documentElement!));
  }

  /// Recursively converts an HTML element into a JSON-serializable map.
  Map<String, dynamic> _elementToJson(html_dom.Element element) {
    return {
      'tag': element.localName,
      'attrs': element.attributes,
      'text': element.text.trim(),
      'html': element.innerHtml,
      'children': element.children.map(_elementToJson).toList(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // CSS Selector query — called from JS wrapper
  // ═══════════════════════════════════════════════════════════════════

  /// Runs a CSS selector query on the given HTML and returns matching
  /// elements as a JSON array.
  String querySelectorAll(String htmlString, String selector) {
    final document = html_parser.parse(htmlString);
    final elements = document.querySelectorAll(selector);
    return jsonEncode(
      elements.map(_elementToJson).toList(),
    );
  }

  /// Runs a CSS selector query and returns the first match (or null).
  String? querySelector(String htmlString, String selector) {
    final document = html_parser.parse(htmlString);
    final element = document.querySelector(selector);
    if (element == null) return null;
    return jsonEncode(_elementToJson(element));
  }

  // ═══════════════════════════════════════════════════════════════════
  // crypto.md5(input) → string
  // ═══════════════════════════════════════════════════════════════════

  String cryptoMd5(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  // ═══════════════════════════════════════════════════════════════════
  // crypto.base64Encode / base64Decode
  // ═══════════════════════════════════════════════════════════════════

  String cryptoBase64Encode(String input) {
    return base64.encode(utf8.encode(input));
  }

  String cryptoBase64Decode(String input) {
    try {
      return utf8.decode(base64.decode(input));
    } catch (_) {
      return '';
    }
  }
}

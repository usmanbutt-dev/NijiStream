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
class BridgeFunctions {
  final Dio _dio;

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

  // ═══════════════════════════════════════════════════════════════════
  // http.get(url, headers?) → string
  // ═══════════════════════════════════════════════════════════════════

  /// Performs an HTTP GET request and returns the response body as a string.
  Future<String> httpGet(String url, [Map<String, String>? headers]) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
        ),
      );
      return response.data ?? '';
    } on DioException catch (e) {
      return '{"error": "${e.message}"}';
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
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            ...?headers,
          },
          responseType: ResponseType.plain,
        ),
      );
      return response.data ?? '';
    } on DioException catch (e) {
      return '{"error": "${e.message}"}';
    }
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
      elements.map((e) => _elementToJson(e)).toList(),
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

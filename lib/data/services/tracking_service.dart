/// NijiStream — Tracking service.
///
/// Handles OAuth authentication and API calls for AniList and MAL.
///
/// OAuth flow (cross-platform, using localhost callback server):
/// 1. Start a temporary HTTP server on localhost:13579.
/// 2. Open the authorization URL in an external browser via url_launcher.
/// 3. After the user authorizes, the browser redirects to
///    `http://localhost:13579/callback?code=...` (or with a fragment for AniList).
/// 4. The local server captures the redirect, extracts the token/code.
/// 5. Token is stored in FlutterSecureStorage (encrypted at rest).
///
/// This approach works on Windows, Android, and Linux — no custom URI
/// scheme registration or platform-specific deep-link setup needed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';

// ── Constants ──────────────────────────────────────────────────────────────

/// Fixed port for the local OAuth callback server.
/// Must match the redirect URI registered in AniList and MAL app settings.
const _oauthPort = 13579;

/// The redirect URI registered in both AniList and MAL app settings.
const _redirectUri = 'http://localhost:$_oauthPort/callback';

/// AniList client ID and secret (auth code flow requires both).
/// Injected at compile time via --dart-define-from-file=.env
const _anilistClientId = String.fromEnvironment(
  'ANILIST_CLIENT_ID',
  defaultValue: '',
);
const _anilistClientSecret = String.fromEnvironment(
  'ANILIST_CLIENT_SECRET',
  defaultValue: '',
);

/// MAL client ID.
/// Injected at compile time via --dart-define-from-file=.env
const _malClientId = String.fromEnvironment(
  'MAL_CLIENT_ID',
  defaultValue: '',
);

// ── Secure storage keys ────────────────────────────────────────────────────
const _kAnilistToken = 'niji_anilist_token';
const _kAnilistUsername = 'niji_anilist_username';
const _kMalToken = 'niji_mal_token';
const _kMalVerifier = 'niji_mal_verifier'; // PKCE code verifier
const _kMalUsername = 'niji_mal_username';

// Shared FlutterSecureStorage instance — platform defaults:
//   Android: EncryptedSharedPreferences
//   Windows: DPAPI (no extra config)
//   Linux: libsecret (requires libsecret-1-dev system package)
const _secureStorage = FlutterSecureStorage();

/// HTML page served after a successful OAuth callback.
const _successHtml = '''
<!DOCTYPE html>
<html>
<head><title>NijiStream</title>
<style>
  body { background: #0F0F14; color: #F0F0F5; font-family: system-ui, sans-serif;
         display: flex; justify-content: center; align-items: center;
         height: 100vh; margin: 0; }
  .box { text-align: center; }
  h2 { color: #A855F7; margin-bottom: 8px; }
  p { color: #A0A0B0; }
</style>
</head>
<body><div class="box">
  <h2>Connected!</h2>
  <p>You can close this tab and return to NijiStream.</p>
</div></body>
</html>
''';


// ── State ──────────────────────────────────────────────────────────────────

class TrackingAccountState {
  final bool anilistConnected;
  final String? anilistUsername;
  final bool malConnected;
  final String? malUsername;
  final bool isLoading;
  final String? error;

  const TrackingAccountState({
    this.anilistConnected = false,
    this.anilistUsername,
    this.malConnected = false,
    this.malUsername,
    this.isLoading = false,
    this.error,
  });

  /// Whether the AniList credentials were provided at compile time.
  bool get anilistConfigured =>
      _anilistClientId.isNotEmpty && _anilistClientSecret.isNotEmpty;

  /// Whether the MAL client ID was provided at compile time.
  bool get malConfigured => _malClientId.isNotEmpty;

  TrackingAccountState copyWith({
    bool? anilistConnected,
    String? anilistUsername,
    bool? malConnected,
    String? malUsername,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return TrackingAccountState(
      anilistConnected: anilistConnected ?? this.anilistConnected,
      anilistUsername: anilistUsername ?? this.anilistUsername,
      malConnected: malConnected ?? this.malConnected,
      malUsername: malUsername ?? this.malUsername,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ───────────────────────────────────────────────────────────────

class TrackingNotifier extends StateNotifier<TrackingAccountState> {
  final AppDatabase _db;
  final _dio = Dio();

  HttpServer? _activeServer;

  TrackingNotifier(this._db) : super(const TrackingAccountState()) {
    _loadStoredAccounts();
  }

  @override
  void dispose() {
    _activeServer?.close(force: true);
    super.dispose();
  }

  // ── Initialisation ──────────────────────────────────────────────

  Future<void> _loadStoredAccounts() async {
    final anilistToken = await _secureStorage.read(key: _kAnilistToken);
    final anilistUser = await _secureStorage.read(key: _kAnilistUsername);
    final malToken = await _secureStorage.read(key: _kMalToken);
    final malUser = await _secureStorage.read(key: _kMalUsername);

    state = state.copyWith(
      anilistConnected: anilistToken != null,
      anilistUsername: anilistUser,
      malConnected: malToken != null,
      malUsername: malUser,
    );
  }

  // ── Local OAuth callback server ────────────────────────────────

  /// Start a temporary HTTP server on [_oauthPort] that waits for the
  /// OAuth provider to redirect the browser back with a code or token.
  ///
  /// Returns the callback [Uri] containing query parameters, or null
  /// if the flow timed out or was cancelled.
  Future<Uri?> _waitForOAuthCallback({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    // Close any previous server (e.g. from a cancelled flow).
    await _activeServer?.close(force: true);

    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _oauthPort,
      );
      _activeServer = server;

      final completer = Completer<Uri?>();

      // Timeout guard.
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(null);
          server.close(force: true);
        }
      });

      server.listen((HttpRequest request) async {
        // Only handle requests to /callback
        if (request.uri.path != '/callback') {
          request.response
            ..statusCode = 404
            ..write('Not found');
          await request.response.close();
          return;
        }

        // We have query params (code from AniList or MAL).
        // Serve the success page and complete.
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_successHtml);
        await request.response.close();

        if (!completer.isCompleted) {
          completer.complete(request.uri);
        }

        // Give the browser a moment to render the success page, then
        // shut down the server.
        Future.delayed(const Duration(seconds: 1), () {
          server.close(force: true);
        });
      });

      final result = await completer.future;
      timer.cancel();
      _activeServer = null;
      return result;
    } on SocketException catch (e) {
      debugPrint('OAuth server bind failed: $e');
      _activeServer = null;
      return null;
    }
  }

  // ── AniList OAuth ───────────────────────────────────────────────

  /// AniList uses Authorization Code flow:
  /// 1. User authorizes in browser → redirected to localhost with ?code=...
  /// 2. We exchange the code + client_secret for an access token.
  Future<void> connectAnilist() async {
    if (_activeServer != null) {
      debugPrint('TrackingService: OAuth flow already in progress');
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final authUrl = Uri.parse(
        '${ApiUrls.anilistAuth}'
        '?client_id=$_anilistClientId'
        '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
        '&response_type=code',
      );

      // Start the callback server BEFORE opening the browser.
      final callbackFuture = _waitForOAuthCallback();

      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        await _activeServer?.close(force: true);
        _activeServer = null;
        state = state.copyWith(
          isLoading: false,
          error: 'Could not open browser for AniList login.',
        );
        return;
      }

      final callbackUri = await callbackFuture;
      if (callbackUri == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'AniList login timed out or was cancelled.',
        );
        return;
      }

      final code = callbackUri.queryParameters['code'];
      if (code == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'AniList did not return an authorization code.',
        );
        return;
      }

      // Exchange code for access token
      final tokenResp = await _dio.post(
        ApiUrls.anilistToken,
        data: jsonEncode({
          'grant_type': 'authorization_code',
          'client_id': _anilistClientId,
          'client_secret': _anilistClientSecret,
          'redirect_uri': _redirectUri,
          'code': code,
        }),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      final tokenBody = tokenResp.data as Map<String, dynamic>?;
      final token = tokenBody?['access_token'] as String?;
      if (token == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'AniList token exchange failed.',
        );
        return;
      }

      // Fetch the viewer's username
      final username = await _fetchAnilistUsername(token);

      // Persist token in secure storage (NOT SharedPreferences)
      await _secureStorage.write(key: _kAnilistToken, value: token);
      if (username != null) {
        await _secureStorage.write(key: _kAnilistUsername, value: username);
      }
      await _upsertDbAccount(service: 'anilist', username: username);

      state = state.copyWith(
        isLoading: false,
        anilistConnected: true,
        anilistUsername: username,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'AniList error: $e');
    }
  }

  Future<String?> _fetchAnilistUsername(String token) async {
    try {
      final resp = await _dio.post(
        ApiUrls.anilistGraphQL,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          'query': '{ Viewer { name } }',
        }),
      );
      final body = resp.data as Map<String, dynamic>?;
      final data = body?['data'] as Map<String, dynamic>?;
      final viewer = data?['Viewer'] as Map<String, dynamic>?;
      return viewer?['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnectAnilist() async {
    await _secureStorage.delete(key: _kAnilistToken);
    await _secureStorage.delete(key: _kAnilistUsername);
    await _db.deleteTrackingAccount('anilist');
    state = state.copyWith(
      anilistConnected: false,
      anilistUsername: null,
    );
  }

  // ── MAL OAuth (PKCE) ────────────────────────────────────────────

  Future<void> connectMal() async {
    if (_activeServer != null) {
      debugPrint('TrackingService: OAuth flow already in progress');
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Generate cryptographically random PKCE code verifier + challenge
      final verifier = _generateCodeVerifier();
      final challenge = verifier; // MAL supports plain challenge

      await _secureStorage.write(key: _kMalVerifier, value: verifier);

      final authUrl = Uri.parse(
        '${ApiUrls.malAuth}'
        '?response_type=code'
        '&client_id=$_malClientId'
        '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
        '&code_challenge=$challenge'
        '&code_challenge_method=plain',
      );

      // Start the callback server BEFORE opening the browser.
      final callbackFuture = _waitForOAuthCallback();

      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        await _activeServer?.close(force: true);
        _activeServer = null;
        state = state.copyWith(
          isLoading: false,
          error: 'Could not open browser for MAL login.',
        );
        return;
      }

      final callbackUri = await callbackFuture;
      if (callbackUri == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'MAL login timed out or was cancelled.',
        );
        return;
      }

      final code = callbackUri.queryParameters['code'];
      if (code == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'MAL did not return an authorization code.',
        );
        return;
      }

      // Exchange code for token
      final tokenResp = await _dio.post(
        ApiUrls.malToken,
        data: {
          'client_id': _malClientId,
          'code': code,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': _redirectUri,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final tokenBody = tokenResp.data as Map<String, dynamic>?;
      final accessToken = tokenBody?['access_token'] as String?;
      if (accessToken == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'MAL token exchange failed.',
        );
        return;
      }

      final refreshToken = tokenBody?['refresh_token'] as String?;
      final username = await _fetchMalUsername(accessToken);

      // Persist tokens in secure storage
      await _secureStorage.write(key: _kMalToken, value: accessToken);
      if (refreshToken != null) {
        await _secureStorage.write(
            key: '${_kMalToken}_refresh', value: refreshToken);
      }
      if (username != null) {
        await _secureStorage.write(key: _kMalUsername, value: username);
      }
      // Clean up verifier — no longer needed after token exchange
      await _secureStorage.delete(key: _kMalVerifier);

      await _upsertDbAccount(service: 'mal', username: username);

      state = state.copyWith(
        isLoading: false,
        malConnected: true,
        malUsername: username,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'MAL error: $e');
    }
  }

  Future<String?> _fetchMalUsername(String token) async {
    try {
      final resp = await _dio.get(
        '${ApiUrls.malApi}/users/@me',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return (resp.data as Map<String, dynamic>?)?['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnectMal() async {
    await _secureStorage.delete(key: _kMalToken);
    await _secureStorage.delete(key: '${_kMalToken}_refresh');
    await _secureStorage.delete(key: _kMalVerifier);
    await _secureStorage.delete(key: _kMalUsername);
    await _db.deleteTrackingAccount('mal');
    state = state.copyWith(
      malConnected: false,
      malUsername: null,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  /// Upsert a tracking account — only stores non-sensitive metadata in DB.
  /// Tokens are kept exclusively in FlutterSecureStorage.
  Future<void> _upsertDbAccount({
    required String service,
    String? username,
  }) async {
    await _db.upsertTrackingAccount(TrackingAccountsTableCompanion.insert(
      id: service,
      service: service,
      username: Value(username),
      // Tokens intentionally NOT stored in SQLite — use secure storage instead.
      accessToken: const Value(null),
      refreshToken: const Value(null),
    ));
  }

  /// Generates a cryptographically random PKCE code verifier (64 chars, URL-safe).
  ///
  /// Uses [Random.secure()] which is backed by the OS CSPRNG, not a clock.
  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    return List.generate(64, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final trackingProvider =
    StateNotifierProvider<TrackingNotifier, TrackingAccountState>((ref) {
  return TrackingNotifier(ref.read(databaseProvider));
});

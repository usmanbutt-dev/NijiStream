/// NijiStream — Tracking service.
///
/// Handles OAuth authentication and API calls for AniList and MAL.
///
/// OAuth flow (both services use browser-based OAuth 2.0):
/// 1. Open the authorization URL in an external browser via url_launcher.
/// 2. The browser redirects to `nijistream://oauth?code=...&state=...`
/// 3. app_links captures that deep-link and we exchange the code for a token.
/// 4. Token is stored in FlutterSecureStorage.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';

// ── Constants ──────────────────────────────────────────────────────────────

/// The redirect URI registered in both AniList and MAL app settings.
const _redirectUri = 'nijistream://oauth';

/// AniList client ID (public — no secret for implicit flow).
/// Users can override this via Settings, but this default works for testing.
const _anilistClientId = 'YOUR_ANILIST_CLIENT_ID';

/// MAL client ID. Users must register their own at myanimelist.net/apiconfig.
const _malClientId = 'YOUR_MAL_CLIENT_ID';

// ── Secure storage keys ────────────────────────────────────────────────────
const _kAnilistToken = 'niji_anilist_token';
const _kAnilistUsername = 'niji_anilist_username';
const _kMalToken = 'niji_mal_token';
const _kMalVerifier = 'niji_mal_verifier'; // PKCE code verifier
const _kMalUsername = 'niji_mal_username';

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
  final _appLinks = AppLinks();

  StreamSubscription<Uri>? _linkSub;
  Completer<Uri?>? _oauthCompleter;

  TrackingNotifier(this._db) : super(const TrackingAccountState()) {
    _loadStoredAccounts();
    _listenForDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  // ── Initialisation ──────────────────────────────────────────────

  Future<void> _loadStoredAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final anilistToken = prefs.getString(_kAnilistToken);
    final anilistUser = prefs.getString(_kAnilistUsername);
    final malToken = prefs.getString(_kMalToken);
    final malUser = prefs.getString(_kMalUsername);

    state = state.copyWith(
      anilistConnected: anilistToken != null,
      anilistUsername: anilistUser,
      malConnected: malToken != null,
      malUsername: malUser,
    );
  }

  void _listenForDeepLinks() {
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'nijistream' && uri.host == 'oauth') {
        _oauthCompleter?.complete(uri);
        _oauthCompleter = null;
      }
    });
  }

  /// Wait for a deep-link redirect, timing out after [timeout].
  Future<Uri?> _waitForRedirect({
    Duration timeout = const Duration(minutes: 5),
  }) {
    _oauthCompleter = Completer<Uri?>();
    Future.delayed(timeout, () {
      if (_oauthCompleter != null && !_oauthCompleter!.isCompleted) {
        _oauthCompleter!.complete(null);
        _oauthCompleter = null;
      }
    });
    return _oauthCompleter!.future;
  }

  // ── AniList OAuth ───────────────────────────────────────────────

  /// AniList uses an implicit OAuth flow (access token returned directly
  /// in the fragment, not a code exchange).  The redirect URI looks like:
  ///   nijistream://oauth#access_token=TOKEN&token_type=Bearer&expires_in=N
  Future<void> connectAnilist() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final authUrl = Uri.parse(
        '${ApiUrls.anilistAuth}'
        '?client_id=$_anilistClientId'
        '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
        '&response_type=token',
      );

      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not open browser for AniList login.',
        );
        return;
      }

      // Wait for the deep-link redirect
      final redirectUri = await _waitForRedirect();
      if (redirectUri == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'AniList login timed out or was cancelled.',
        );
        return;
      }

      // AniList returns the token in the URI fragment (#access_token=...)
      // app_links surfaces the fragment as the `fragment` property.
      final fragment = redirectUri.fragment;
      final params = Uri.splitQueryString(fragment);
      final token = params['access_token'];

      if (token == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'AniList did not return an access token.',
        );
        return;
      }

      // Fetch the viewer's username
      final username = await _fetchAnilistUsername(token);

      // Persist
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAnilistToken, token);
      if (username != null) {
        await prefs.setString(_kAnilistUsername, username);
      }
      await _upsertDbAccount(
        service: 'anilist',
        token: token,
        username: username,
      );

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
      return resp.data['data']?['Viewer']?['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnectAnilist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAnilistToken);
    await prefs.remove(_kAnilistUsername);
    await _db.deleteTrackingAccount('anilist');
    state = state.copyWith(
      anilistConnected: false,
      anilistUsername: null,
    );
  }

  // ── MAL OAuth (PKCE) ────────────────────────────────────────────

  Future<void> connectMal() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Generate PKCE code verifier + challenge
      final verifier = _generateCodeVerifier();
      final challenge = verifier; // MAL supports plain challenge

      final verifierPrefs = await SharedPreferences.getInstance();
      await verifierPrefs.setString(_kMalVerifier, verifier);

      final authUrl = Uri.parse(
        '${ApiUrls.malAuth}'
        '?response_type=code'
        '&client_id=$_malClientId'
        '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
        '&code_challenge=$challenge'
        '&code_challenge_method=plain',
      );

      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not open browser for MAL login.',
        );
        return;
      }

      final redirectUri = await _waitForRedirect();
      if (redirectUri == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'MAL login timed out or was cancelled.',
        );
        return;
      }

      final code = redirectUri.queryParameters['code'];
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

      final accessToken = tokenResp.data['access_token'] as String?;
      if (accessToken == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'MAL token exchange failed.',
        );
        return;
      }

      final refreshToken = tokenResp.data['refresh_token'] as String?;
      final username = await _fetchMalUsername(accessToken);

      final malPrefs = await SharedPreferences.getInstance();
      await malPrefs.setString(_kMalToken, accessToken);
      if (username != null) {
        await malPrefs.setString(_kMalUsername, username);
      }
      await _upsertDbAccount(
        service: 'mal',
        token: accessToken,
        refreshToken: refreshToken,
        username: username,
      );

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
      return resp.data['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnectMal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMalToken);
    await prefs.remove(_kMalVerifier);
    await prefs.remove(_kMalUsername);
    await _db.deleteTrackingAccount('mal');
    state = state.copyWith(
      malConnected: false,
      malUsername: null,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  Future<void> _upsertDbAccount({
    required String service,
    required String token,
    String? refreshToken,
    String? username,
  }) async {
    await _db.upsertTrackingAccount(TrackingAccountsTableCompanion(
      id: Value(service),
      service: Value(service),
      username: Value(username),
      accessToken: Value(token),
      refreshToken: Value(refreshToken),
    ));
  }

  /// Generates a random PKCE code verifier (43–128 chars, URL-safe).
  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = List.generate(
        64, (index) => chars[(DateTime.now().microsecondsSinceEpoch + index * 7) % chars.length]);
    return rand.join();
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final trackingProvider =
    StateNotifierProvider<TrackingNotifier, TrackingAccountState>((ref) {
  return TrackingNotifier(ref.read(databaseProvider));
});

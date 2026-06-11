import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/spotify_buddy_service.dart';
import '../models/user.dart';
import '../services/spotify_token_service.dart';
import '../services/app_logger.dart';

enum AuthState { uninitialized, loading, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  static const String _bearerTokenKey = 'spotify_bearer_token';
  static const String _headersKey = 'spotify_headers';
  static const String _userKey = 'spotify_user';
  static const String _spDcKey = 'spotify_sp_dc';

  final SharedPreferences _prefs;
  final SpotifyBuddyService _buddyService = SpotifyBuddyService();

  String? _bearerToken;
  Map<String, String>? _headers;
  User? _currentUser;
  String? _spDc;
  AuthState _authState = AuthState.uninitialized;

  final List<String> _authEvents = [];
  String? _lastAuthError;

  List<String> get authEvents => List.unmodifiable(_authEvents);
  String? get lastAuthError => _lastAuthError;

  void _addEvent(String msg) {
    final t = DateTime.now();
    final ts = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    _authEvents.add('[$ts] $msg');
    if (_authEvents.length > 30) _authEvents.removeAt(0);
    AppLogger.auth(msg);
    notifyListeners();
  }

  /// Injectable token fetcher — override in tests to avoid real network calls.
  @visibleForTesting
  Future<String?> Function(String spDc)? tokenFetchOverride;

  /// Injectable user-profile fetcher — override in tests.
  @visibleForTesting
  Future<User?> Function(String bearerToken)? userProfileFetchOverride;

  AuthProvider(this._prefs) {
    // Scheduled as a microtask so callers (including tests) can set overrides
    // on the instance before initialization reads them.
    Future.microtask(_initializeAuth);
  }

  AuthState get authState => _authState;
  bool get isAuthenticated => _authState == AuthState.authenticated;
  bool get isLoading => _authState == AuthState.loading;
  bool get isInitialized => _authState != AuthState.uninitialized;
  User? get currentUser => _currentUser;
  String? get bearerToken => _bearerToken;
  Map<String, String>? get headers => _headers;

  Future<void> _initializeAuth() async {
    _authState = AuthState.loading;
    notifyListeners();

    try {
      _addEvent('Starting auth initialization...');
      _loadStoredData();

      final savedBearerToken = _prefs.getString(_bearerTokenKey);
      final savedHeadersJson = _prefs.getString(_headersKey);
      final savedUserJson = _prefs.getString(_userKey);

      _spDc = _prefs.getString(_spDcKey);

      if (savedBearerToken != null && savedHeadersJson != null) {
        try {
          _bearerToken = savedBearerToken;
          _headers = Map<String, String>.from(json.decode(savedHeadersJson));
          _addEvent('Restored saved token + headers');

          if (savedUserJson != null) {
            // Trust the stored profile — it was fetched correctly via WebView JS
            // injection at login time. Server-side re-fetching is blocked by Spotify's
            // rate limiter (429); a stale token will surface as 401 on the first API
            // call and trigger _trySilentRefresh at that point.
            final userMap = json.decode(savedUserJson);
            _currentUser = User.fromJson(userMap);

            // One-time migration: scrub placeholder values written by older app
            // versions that hardcoded 'user@spotify.com' and 'US' as fallbacks.
            if (_currentUser!.email == 'user@spotify.com') {
              _currentUser = User(
                id: _currentUser!.id,
                displayName: _currentUser!.displayName,
                email: '',
                imageUrl: _currentUser!.imageUrl,
                followers: _currentUser!.followers,
                country: _currentUser!.country == 'US' ? '' : _currentUser!.country,
              );
              await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
              _addEvent('Scrubbed stale placeholder email/country from stored profile');
            }

            _addEvent('Restored: ${_currentUser!.displayName}');

            // Proactively refresh the bearer token if sp_dc is available.
            // Spotify tokens expire in ~1h; a cold start hours after the last
            // session would use an expired token and cause all API calls to fail
            // with 401. Refreshing here costs one network round-trip on startup
            // but prevents the cascading failures that would otherwise require
            // the error-recovery flow to trigger and re-fetch everything.
            if (_spDc != null) {
              _addEvent('Proactively refreshing token with sp_dc...');
              final ok = await _trySilentRefresh();
              if (!ok) {
                _addEvent('Proactive refresh failed — proceeding with stored token');
              }
            }
          } else {
            // Token present but no user — try silent refresh to obtain profile.
            _addEvent('Token without user — trying silent refresh...');
            final didRefresh = await _trySilentRefresh();
            if (!didRefresh) {
              await _clearStoredData();
            }
          }
        } catch (e) {
          _addEvent('Restore error — trying silent refresh');
          _lastAuthError = 'Restore: $e';
          final didRefresh = await _trySilentRefresh();
          if (!didRefresh) {
            await _clearStoredData();
          }
        }
      } else if (_spDc != null) {
        _addEvent('No stored token — silent refresh with sp_dc...');
        await _trySilentRefresh();
      } else {
        _addEvent('No credentials found');
      }

      _addEvent('Init complete — token:${_bearerToken != null} user:${_currentUser?.displayName ?? "none"}');

    } catch (e) {
      _lastAuthError = 'Init error: $e';
      AppLogger.error('Error during auth initialization', e);
    } finally {
      _authState = _bearerToken != null && _currentUser != null
          ? AuthState.authenticated
          : AuthState.unauthenticated;
      _addEvent('State -> ${_authState.name}');
      notifyListeners();
    }
  }

  void _loadStoredData() {
    _prefs.remove('spotify_sp_dc_cookie');
    _prefs.remove('spotify_access_token');
    _prefs.remove('spotify_refresh_token');
    _prefs.remove('spotify_token_expiry');
  }

  Future<void> loginComplete(String bearerToken, Map<String, String> headers) async {
    _authState = AuthState.loading;
    _lastAuthError = null;
    notifyListeners();

    try {
      _addEvent('loginComplete: token len=${bearerToken.length} headers=${headers.keys.join(",")}');

      if (bearerToken.isEmpty || bearerToken.length < 50) {
        throw Exception('Invalid bearer token (len=${bearerToken.length})');
      }

      final cookieHeader = headers['Cookie'] ?? '';
      final extractedSpDc = SpotifyTokenService.extractSpDc(cookieHeader);
      if (extractedSpDc != null && extractedSpDc.isNotEmpty) {
        _spDc = extractedSpDc;
        _addEvent('sp_dc extracted (len=${extractedSpDc.length})');
      } else {
        _addEvent('WARNING: sp_dc not found in headers');
      }

      _bearerToken = bearerToken;
      _headers = headers;

      User? userProfile;

      // WebView pre-fetched profile via JS injection (avoids server-side rate limit).
      final prefetchedJson = headers['x-prefetched-user'];
      if (prefetchedJson != null) {
        try {
          final m = json.decode(prefetchedJson) as Map<String, dynamic>;
          final id = m['id'] as String? ?? '';
          if (id.isNotEmpty) {
            userProfile = User(
              id: id,
              displayName: m['displayName'] as String? ?? id,
              email: m['email'] as String? ?? '',
              imageUrl: m['imageUrl'] as String?,
              followers: m['followers'] as int? ?? 0,
              country: m['country'] as String? ?? '',
            );
            _addEvent('Profile from WebView JS: ${userProfile.displayName}');
          }
        } catch (e) {
          _addEvent('Failed to parse prefetched user: $e');
        }
      }

      // Server-side fallback — only used when WebView JS injection failed.
      // api.spotify.com/v1/me is rate-limited (429) for web-player tokens from
      // server-side Dart, so we only try once to fail fast rather than spinning
      // for 75+ seconds across 5 retries.
      if (userProfile == null) {
        final profileFetcher = userProfileFetchOverride ??
            _buddyService.getCurrentUserProfileWithToken;
        try {
          _addEvent('Profile fetch (server-side fallback)...');
          userProfile = await profileFetcher(_bearerToken!);
          if (userProfile != null) {
            _addEvent('Profile loaded: ${userProfile.displayName}');
          }
        } catch (e) {
          _lastAuthError = '$e';
          _addEvent('Server-side profile fetch failed: $e');
        }
      }

      if (userProfile == null) {
        throw Exception('Could not load profile. Please try logging in again.');
      }

      // Enrich with email/country if WebView JS didn't capture them.
      if ((userProfile.email.isEmpty || userProfile.country.isEmpty) && _spDc != null) {
        final acct = await SpotifyTokenService.fetchAccountProfile(_spDc!);
        if (acct != null) {
          userProfile = User(
            id: userProfile.id,
            displayName: userProfile.displayName,
            email: acct.email.isNotEmpty ? acct.email : userProfile.email,
            imageUrl: userProfile.imageUrl,
            followers: userProfile.followers,
            country: acct.country.isNotEmpty ? acct.country : userProfile.country,
          );
          _addEvent('Email/country enriched from account-settings: ${userProfile.email}');
        }
      }

      _currentUser = userProfile;
      await _saveStoredData();

      _authState = AuthState.authenticated;
      _addEvent('loginComplete SUCCESS: ${_currentUser!.displayName}');

    } catch (e) {
      _lastAuthError = 'loginComplete: $e';
      _addEvent('loginComplete FAILED: $e');
      AppLogger.error('Error in loginComplete', e);

      _bearerToken = null;
      _headers = null;
      _currentUser = null;
      await _clearStoredData();

      _authState = AuthState.unauthenticated;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _saveStoredData() async {
    if (_bearerToken != null) await _prefs.setString(_bearerTokenKey, _bearerToken!);
    if (_headers != null) await _prefs.setString(_headersKey, json.encode(_headers!));
    if (_currentUser != null) await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
    if (_spDc != null) await _prefs.setString(_spDcKey, _spDc!);
    _addEvent('Auth data saved');
  }

  Future<void> _clearStoredData() async {
    await _prefs.remove(_bearerTokenKey);
    await _prefs.remove(_headersKey);
    await _prefs.remove(_userKey);
    // sp_dc intentionally NOT removed — survives token expiry for silent refresh.
    _bearerToken = null;
    _headers = null;
    _currentUser = null;
    _addEvent('Auth data cleared');
  }

  Future<void> logout() async {
    _addEvent('Logout requested');
    await _clearStoredData();
    await _prefs.remove(_spDcKey);
    _spDc = null;
    _buddyService.clearActivityCache();
    _authState = AuthState.unauthenticated;
    _addEvent('Logged out');
    notifyListeners();
  }

  bool _isRecovering = false;

  /// Attempts to recover from a 401 without showing the login screen.
  ///
  /// Fast path: read sp_dc directly from the WebView cookie store (instant,
  /// no page load required). If the cookie is already there, exchange it for
  /// a fresh bearer token via a single HTTP call.
  ///
  /// Slow path (fallback): load open.spotify.com in a headless WebView so
  /// Spotify can issue a fresh sp_dc using the long-lived OAuth session.
  ///
  /// Returns true when the app is successfully re-authenticated.
  Future<bool> tryRecoverFromExpiredToken() async {
    if (_isRecovering) {
      _addEvent('Recovery already in progress — skipping duplicate call');
      return false;
    }
    _isRecovering = true;
    _addEvent('Token recovery: starting...');
    try {
      // Fast path: read sp_dc directly from the WebView cookie jar — no page
      // load, just a cookie store read. This completes in milliseconds.
      final cookies = await CookieManager.instance()
          .getCookies(url: WebUri('https://open.spotify.com'));
      final spDcCookie = cookies.firstWhere(
        (c) => c.name == 'sp_dc' && (c.value as String).isNotEmpty,
        orElse: () => Cookie(name: '', value: ''),
      );
      final cookieSpDc = spDcCookie.name.isNotEmpty
          ? spDcCookie.value as String
          : null;

      if (cookieSpDc != null && cookieSpDc != _spDc) {
        // Fresh sp_dc found in cookie jar — save it and try a silent refresh.
        _addEvent('Token recovery: fresh sp_dc found in cookie store (fast path)');
        _spDc = cookieSpDc;
        await _prefs.setString(_spDcKey, cookieSpDc);
        final ok = await _trySilentRefresh();
        if (ok) {
          _authState = AuthState.authenticated;
          _addEvent('Token recovery: OK via cookie-store fast path');
          notifyListeners();
          return true;
        }
      } else if (cookieSpDc == _spDc && cookieSpDc != null) {
        // Same sp_dc in store — bearer may have just expired, try refresh directly.
        _addEvent('Token recovery: sp_dc unchanged, refreshing bearer token');
        final ok = await _trySilentRefresh();
        if (ok) {
          _authState = AuthState.authenticated;
          _addEvent('Token recovery: OK via bearer refresh');
          notifyListeners();
          return true;
        }
      }

      // Slow path: load a page so Spotify can issue a fresh sp_dc.
      _addEvent('Token recovery: fast path failed, starting headless WebView...');
      final ok = await _tryHeadlessWebViewReAuth();
      if (ok) {
        _authState = AuthState.authenticated;
        _addEvent('Token recovery: OK via headless WebView');
        notifyListeners();
        return true;
      }

      _addEvent('Token recovery: all paths failed — need login');
      return false;
    } finally {
      _isRecovering = false;
    }
  }

  /// Loads open.spotify.com in an invisible WebView so Spotify can issue a
  /// fresh sp_dc using the long-lived OAuth session stored in the browser.
  /// Returns true when a new (different) sp_dc is obtained and the silent
  /// token refresh succeeds.
  Future<bool> _tryHeadlessWebViewReAuth() async {
    _addEvent('Headless WebView re-auth: starting...');
    final completer = Completer<String?>();
    HeadlessInAppWebView? headless;
    Timer? timeout;

    Future<void> checkForSpDc(InAppWebViewController controller) async {
      if (completer.isCompleted) return;
      try {
        final cookies = await CookieManager.instance()
            .getCookies(url: WebUri('https://open.spotify.com'));
        final spDcCookie = cookies.firstWhere(
          (c) => c.name == 'sp_dc' && (c.value as String).isNotEmpty,
          orElse: () => Cookie(name: '', value: ''),
        );
        if (spDcCookie.name.isNotEmpty && !completer.isCompleted) {
          completer.complete(spDcCookie.value as String);
        }
      } catch (e) {
        if (!completer.isCompleted) completer.complete(null);
      }
    }

    try {
      headless = HeadlessInAppWebView(
        initialSize: const Size(1, 1),
        initialUrlRequest: URLRequest(
          url: WebUri('https://open.spotify.com/'),
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: SpotifyTokenService.userAgent,
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
        ),
        onLoadStop: (controller, url) async {
          if (completer.isCompleted || url == null) return;
          final urlStr = url.toString();
          if (urlStr.contains('accounts.spotify.com') ||
              urlStr.contains('/login') ||
              urlStr.contains('/auth/')) {
            _addEvent('Headless WebView: redirected to login — OAuth session gone');
            if (!completer.isCompleted) completer.complete(null);
            return;
          }
          if (!urlStr.contains('open.spotify.com')) return;
          await checkForSpDc(controller);
          if (!completer.isCompleted) {
            await Future.delayed(const Duration(seconds: 2));
            await checkForSpDc(controller);
            if (!completer.isCompleted) completer.complete(null);
          }
        },
        onReceivedError: (_, a, b) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );

      await headless.run();
      timeout = Timer(const Duration(seconds: 20), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      final newSpDc = await completer.future;
      if (newSpDc == null || newSpDc.isEmpty) {
        _addEvent('Headless WebView re-auth: no sp_dc obtained');
        return false;
      }
      if (newSpDc == _spDc) {
        _addEvent('Headless WebView re-auth: sp_dc unchanged — already tried this value');
        return false;
      }

      _addEvent('Headless WebView re-auth: fresh sp_dc obtained');
      _spDc = newSpDc;
      await _prefs.setString(_spDcKey, newSpDc);
      return await _trySilentRefresh();
    } catch (e) {
      _addEvent('Headless WebView re-auth error: $e');
      return false;
    } finally {
      timeout?.cancel();
      try { await headless?.dispose(); } catch (_) {}
    }
  }

  /// Refresh the token if currently authenticated. Returns false if not
  /// authenticated or if the silent refresh fails.
  Future<bool> refreshIfNeeded() async {
    if (_authState != AuthState.authenticated) return false;
    final ok = await _trySilentRefresh();
    if (!ok) {
      _authState = AuthState.unauthenticated;
      notifyListeners();
    }
    return ok;
  }

  /// Attempts to silently obtain a fresh Bearer token using the stored sp_dc.
  /// Updates internal state and storage on success. Returns true on success.
  Future<bool> _trySilentRefresh() async {
    final spDc = _spDc ?? _prefs.getString(_spDcKey);
    if (spDc == null || spDc.isEmpty) {
      _addEvent('Silent refresh skipped: no sp_dc');
      return false;
    }

    _addEvent('Silent refresh starting...');
    final fetcher = tokenFetchOverride ?? SpotifyTokenService.fetchBearerToken;
    final newToken = await fetcher(spDc);
    if (newToken == null || newToken.isEmpty) {
      _addEvent('Silent refresh: no token returned');
      return false;
    }

    _spDc = spDc;
    _bearerToken = newToken;
    _headers = SpotifyTokenService.headersFromSpDc(spDc);

    // Only fetch profile when we don't already have one. Existing profile was
    // obtained via WebView JS injection and is correct; spclient/profile/me
    // returns a different account (social profile, not account settings).
    if (_currentUser == null) {
      try {
        final profileFetcher = userProfileFetchOverride ??
            _buddyService.getCurrentUserProfileWithToken;
        _currentUser = await profileFetcher(newToken);
      } catch (e) {
        _addEvent('Silent refresh: profile fetch failed: $e');
        _lastAuthError = 'Silent refresh profile: $e';
      }

      if (_currentUser == null) {
        _addEvent('Silent refresh: no profile — aborting');
        _bearerToken = null;
        _headers = null;
        return false;
      }
    }

    // Enrich with email/country when missing — spclient doesn't return these.
    // account-settings/v1/profile works with just sp_dc, no OAuth scopes needed.
    if (_currentUser!.email.isEmpty || _currentUser!.country.isEmpty) {
      final acct = await SpotifyTokenService.fetchAccountProfile(spDc);
      if (acct != null) {
        _currentUser = User(
          id: _currentUser!.id,
          displayName: _currentUser!.displayName,
          email: acct.email.isNotEmpty ? acct.email : _currentUser!.email,
          imageUrl: _currentUser!.imageUrl,
          followers: _currentUser!.followers,
          country: acct.country.isNotEmpty ? acct.country : _currentUser!.country,
        );
        _addEvent('Silent refresh: email/country enriched (${_currentUser!.email})');
      }
    }

    await _saveStoredData();
    _addEvent('Silent refresh OK: ${_currentUser!.displayName}');
    notifyListeners();
    return true;
  }
}
